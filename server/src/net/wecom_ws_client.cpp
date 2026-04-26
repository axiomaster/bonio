#include "hiclaw/net/wecom_ws_client.hpp"
#include "hiclaw/observability/log.hpp"
#include <hv/WebSocketClient.h>
#include <nlohmann/json.hpp>

#ifdef _WIN32
#undef min
#undef max
#endif

#include <algorithm>
#include <chrono>
#include <thread>

namespace hiclaw {
namespace net {

namespace {

using json = nlohmann::json;

static const char* kWsEndpoint = "wss://openws.work.weixin.qq.com";
static const int kPingIntervalMs = 30000;
static const int kMaxBackoffMs = 30000;
static const int kReplyChunkBytes = 2000;

}  // namespace

WecomWsClient::WecomWsClient(const std::string& bot_id,
                             const std::string& bot_secret)
    : bot_id_(bot_id), bot_secret_(bot_secret) {}

WecomWsClient::~WecomWsClient() {
  stop();
}

std::string WecomWsClient::next_req_id(const std::string& prefix) {
  int64_t seq = req_seq_.fetch_add(1) + 1;
  return prefix + "_" + std::to_string(seq);
}

bool WecomWsClient::send_frame(const std::string& json_frame) {
  std::lock_guard<std::mutex> lock(write_mutex_);
  auto* ws = static_cast<hv::WebSocketClient*>(ws_client_);
  if (!ws) return false;
  int ret = ws->send(json_frame);
  return ret > 0;
}

bool WecomWsClient::subscribe() {
  json frame;
  frame["cmd"] = "aibot_subscribe";
  frame["headers"]["req_id"] = next_req_id("aibot_subscribe");
  frame["body"]["bot_id"] = bot_id_;
  frame["body"]["secret"] = bot_secret_;
  return send_frame(frame.dump());
}

void WecomWsClient::run(WecomMessageCallback on_message) {
  on_message_ = std::move(on_message);
  running_ = true;

  int backoff_ms = 1000;

  while (running_) {
    hv::WebSocketClient ws;
    ws_client_ = &ws;
    ws.setPingInterval(kPingIntervalMs);

    ws.onopen = [this]() {
      log::info("wecom_ws: connected to " + std::string(kWsEndpoint));
      if (!subscribe()) {
        log::error("wecom_ws: failed to send subscribe frame");
      }
    };

    ws.onclose = [this]() {
      log::info("wecom_ws: connection closed");
    };

    ws.onmessage = [this](const std::string& msg) {
      try {
        auto j = json::parse(msg);
        std::string cmd = j.value("cmd", "");
        int errcode = j.value("errcode", 0);

        if (cmd == "aibot_msg_callback") {
          // Inbound user message
          auto& headers = j["headers"];
          std::string req_id = headers.value("req_id", "");
          auto& body = j["body"];
          std::string msg_id = body.value("msgid", "");
          std::string chat_id = body.value("chatid", "");
          std::string chat_type = body.value("chattype", "single");
          std::string user_id;
          if (body.contains("from") && body["from"].is_object()) {
            user_id = body["from"].value("userid", "");
          }
          std::string msg_type = body.value("msgtype", "text");
          std::string content;

          if (msg_type == "text" && body.contains("text") && body["text"].is_object()) {
            content = body["text"].value("content", "");
          } else if (msg_type == "voice") {
            // Prefer transcription text
            if (body.contains("voice") && body["voice"].is_object()) {
              content = body["voice"].value("text", "");
              if (content.empty()) content = body["voice"].value("content", "");
            }
            if (content.empty()) content = "[voice message]";
          } else if (msg_type == "image") {
            content = "[image]";
          } else if (msg_type == "file") {
            content = "[file]";
          } else if (msg_type == "mixed") {
            // Extract text parts from mixed message
            if (body.contains("mixed") && body["mixed"].is_object() &&
                body["mixed"].contains("msg_item") && body["mixed"]["msg_item"].is_array()) {
              for (auto& item : body["mixed"]["msg_item"]) {
                if (item.value("msgtype", "") == "text" &&
                    item.contains("text") && item["text"].is_object()) {
                  if (!content.empty()) content += "\n";
                  content += item["text"].value("content", "");
                }
              }
            }
          }

          // Strip @bot mentions
          std::string at_bot = "@" + bot_id_;
          size_t pos;
          while ((pos = content.find(at_bot)) != std::string::npos) {
            content.erase(pos, at_bot.size());
          }
          // Trim
          while (!content.empty() && (content.front() == ' ' || content.front() == '\n'))
            content.erase(0, 1);
          while (!content.empty() && (content.back() == ' ' || content.back() == '\n'))
            content.pop_back();

          if (!content.empty() && on_message_) {
            on_message_(msg_id, user_id, chat_id, chat_type, content, req_id);
          }
        } else if (cmd == "ping" || cmd == "aibot_ping") {
          // Respond to server ping
          json pong;
          pong["cmd"] = "pong";
          pong["headers"]["req_id"] = j["headers"].value("req_id", "");
          send_frame(pong.dump());
        } else if (errcode != 0 && cmd.empty()) {
          // Response with error
          std::string errmsg = j.value("errmsg", "");
          log::warn("wecom_ws: frame error: errcode=" + std::to_string(errcode) +
                    " errmsg=" + errmsg);
        }
        // Ignore: pong responses, event callbacks, subscribe ack
      } catch (const json::parse_error& e) {
        log::warn("wecom_ws: failed to parse frame: " + std::string(e.what()));
      }
    };

    log::info("wecom_ws: connecting...");
    int ret = ws.open(kWsEndpoint);
    if (ret != 0) {
      log::error("wecom_ws: connection failed, retrying in " +
                 std::to_string(backoff_ms) + "ms");
    }

    // ws.open() with hv::WebSocketClient starts the event loop.
    // When connection drops, we fall through and retry.
    ws_client_ = nullptr;

    if (!running_) break;

    // Exponential backoff
    std::this_thread::sleep_for(std::chrono::milliseconds(backoff_ms));
    backoff_ms = std::min(backoff_ms * 2, kMaxBackoffMs);
  }

  log::info("wecom_ws: stopped");
}

void WecomWsClient::stop() {
  running_ = false;
  auto* ws = static_cast<hv::WebSocketClient*>(ws_client_);
  if (ws) {
    ws->close();
  }
}

bool WecomWsClient::reply(const std::string& callback_req_id,
                          const std::string& content) {
  // Split into chunks if needed (2000 bytes per chunk)
  std::vector<std::string> chunks;
  size_t offset = 0;
  while (offset < content.size()) {
    size_t len = std::min(content.size() - offset, static_cast<size_t>(kReplyChunkBytes));
    // Avoid splitting mid-UTF8
    while (len > 0 && offset + len < content.size()) {
      unsigned char c = static_cast<unsigned char>(content[offset + len]);
      if ((c & 0xC0) == 0x80) {
        --len;  // continuation byte, go back
      } else {
        break;
      }
    }
    if (len == 0) len = 1;
    chunks.push_back(content.substr(offset, len));
    offset += len;
  }

  for (size_t i = 0; i < chunks.size(); ++i) {
    bool is_last = (i == chunks.size() - 1);
    std::string stream_id = "stream_" + std::to_string(i + 1);

    json frame;
    frame["cmd"] = "aibot_respond_msg";
    frame["headers"]["req_id"] = callback_req_id;
    frame["body"]["msgtype"] = "stream";
    frame["body"]["stream"]["id"] = stream_id;
    frame["body"]["stream"]["finish"] = is_last;
    frame["body"]["stream"]["content"] = chunks[i];

    if (!send_frame(frame.dump())) {
      log::error("wecom_ws: failed to send reply chunk " + std::to_string(i + 1));
      return false;
    }
  }
  return true;
}

}  // namespace net
}  // namespace hiclaw
