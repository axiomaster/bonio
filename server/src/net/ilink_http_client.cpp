#include "hiclaw/net/ilink_http_client.hpp"
#include "hiclaw/observability/log.hpp"
#include <hv/HttpClient.h>
#include <nlohmann/json.hpp>
#include <algorithm>
#include <chrono>
#include <cstdlib>
#include <fstream>
#include <random>
#include <sstream>
#include <thread>

#ifdef _WIN32
#undef min
#undef max
#endif

namespace hiclaw {
namespace net {

namespace {

using json = nlohmann::json;

static const int kMaxChunkChars = 3800;
static const int kMaxSendRetries = 3;
static const char* kChannelVersion = "hiclaw-weixin/1.0";

std::string random_hex(int bytes) {
  std::random_device rd;
  std::mt19937 gen(rd());
  std::uniform_int_distribution<int> dist(0, 255);
  std::string result;
  result.reserve(bytes * 2);
  for (int i = 0; i < bytes; ++i) {
    char buf[3];
    snprintf(buf, sizeof(buf), "%02x", dist(gen));
    result += buf;
  }
  return result;
}

std::string random_uin() {
  std::random_device rd;
  std::mt19937 gen(rd());
  std::uniform_int_distribution<uint32_t> dist;
  uint32_t val = dist(gen);
  // Base64 encode the 4 bytes
  static const char kTable[] =
      "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  uint8_t bytes[4];
  bytes[0] = (val >> 24) & 0xFF;
  bytes[1] = (val >> 16) & 0xFF;
  bytes[2] = (val >> 8) & 0xFF;
  bytes[3] = val & 0xFF;
  std::string b64;
  for (int i = 0; i < 4; i += 3) {
    // We only have 4 bytes, encode as-is
    b64 += kTable[bytes[i] >> 2];
    b64 += kTable[((bytes[i] & 0x03) << 4) | (bytes[i + 1] >> 4)];
    b64 += kTable[((bytes[i + 1] & 0x0F) << 2) | (bytes[i + 2] >> 6)];
    b64 += kTable[bytes[i + 2] & 0x3F];
  }
  return b64;
}

std::string read_file(const std::string& path) {
  std::ifstream f(path);
  if (!f.is_open()) return "";
  std::ostringstream ss;
  ss << f.rdbuf();
  return ss.str();
}

bool write_file(const std::string& path, const std::string& data) {
  std::ofstream f(path, std::ios::binary);
  if (!f.is_open()) return false;
  f << data;
  return true;
}

}  // namespace

IlinkHttpClient::IlinkHttpClient(const std::string& token,
                                   const std::string& base_url,
                                   const std::string& state_dir)
    : token_(token), base_url_(base_url), state_dir_(state_dir) {
  client_id_ = "cc-" + random_hex(6);
  x_wechat_uin_ = random_uin();
  load_all_context_tokens();

  log::info("ilink: client initialized, base_url=" + base_url_ +
            " state_dir=" + state_dir_);
}

IlinkHttpClient::~IlinkHttpClient() {
  stop();
}

void IlinkHttpClient::stop() {
  running_ = false;
}

bool IlinkHttpClient::do_post(const std::string& path, const std::string& body,
                               int& ret_code, int& err_code,
                               std::string& resp_body) {
  std::string url = base_url_ + path;

  hv::HttpClient cli;
  cli.setTimeout(60);

  ::HttpRequest req;
  req.method = HTTP_POST;
  req.url = url;
  req.headers["Content-Type"] = "application/json";
  req.headers["AuthorizationType"] = "ilink_bot_token";
  req.headers["Authorization"] = "Bearer " + token_;
  req.headers["X-WECHAT-UIN"] = x_wechat_uin_;
  req.body = body;
  req.timeout = 60;
  req.connect_timeout = 30;

  ::HttpResponse resp;
  int ret = cli.send(&req, &resp);
  if (ret != 0) {
    log::error("ilink: HTTP POST " + path + " failed: " + std::to_string(ret));
    return false;
  }

  resp_body = resp.body;

  if (resp.status_code < 200 || resp.status_code >= 300) {
    log::error("ilink: HTTP " + std::to_string(resp.status_code) +
               " from " + path);
    return false;
  }

  try {
    auto j = json::parse(resp_body);
    ret_code = j.value("ret", 0);
    err_code = j.value("errcode", 0);
  } catch (...) {
    ret_code = -999;
    err_code = -999;
  }
  return true;
}

bool IlinkHttpClient::do_get(const std::string& url, std::string& resp_body) {
  hv::HttpClient cli;
  cli.setTimeout(30);

  ::HttpRequest req;
  req.method = HTTP_GET;
  req.url = url;
  req.timeout = 30;
  req.connect_timeout = 15;

  ::HttpResponse resp;
  int ret = cli.send(&req, &resp);
  if (ret != 0) {
    log::error("ilink: HTTP GET failed: " + std::to_string(ret));
    return false;
  }

  resp_body = resp.body;
  return resp.status_code >= 200 && resp.status_code < 300;
}

std::string IlinkHttpClient::extract_text(const void* item_list_json) {
  auto& items = *static_cast<const json*>(item_list_json);
  if (!items.is_array()) return "";

  std::string result;
  for (auto& item : items) {
    int type = item.value("type", 0);
    if (type == 1) {
      // Text
      if (item.contains("text_item") && item["text_item"].is_object()) {
        if (!result.empty()) result += "\n";
        result += item["text_item"].value("text", "");
      }
    } else if (type == 3) {
      // Voice — use transcription
      if (item.contains("voice_item") && item["voice_item"].is_object()) {
        if (!result.empty()) result += "\n";
        result += item["voice_item"].value("text", "");
      }
    } else if (type == 2) {
      if (!result.empty()) result += "\n";
      result += "[image]";
    } else if (type == 4) {
      if (!result.empty()) result += "\n";
      result += "[file]";
    } else if (type == 5) {
      if (!result.empty()) result += "\n";
      result += "[video]";
    }
  }
  return result;
}

bool IlinkHttpClient::get_updates(std::vector<Message>& msgs) {
  msgs.clear();

  std::string cursor;
  load_cursor(cursor);

  json req_body;
  if (!cursor.empty()) {
    req_body["get_updates_buf"] = cursor;
  }
  req_body["base_info"]["channel_version"] = kChannelVersion;

  int ret_code = 0, err_code = 0;
  std::string resp_body;
  if (!do_post("/ilink/bot/getupdates", req_body.dump(),
               ret_code, err_code, resp_body)) {
    return false;
  }

  try {
    auto j = json::parse(resp_body);

    if (err_code == -14) {
      log::warn("ilink: session expired (errcode=-14), pausing 1 hour");
      std::this_thread::sleep_for(std::chrono::hours(1));
      return false;
    }

    if (ret_code != 0) {
      log::warn("ilink: getupdates ret=" + std::to_string(ret_code));
      return false;
    }

    // Save cursor
    std::string next_cursor = j.value("get_updates_buf", "");
    if (!next_cursor.empty()) {
      save_cursor(next_cursor);
    }

    if (!j.contains("msgs") || !j["msgs"].is_array()) return true;

    for (auto& m : j["msgs"]) {
      Message msg;
      msg.message_id = m.value("message_id", (int64_t)0);
      msg.seq = m.value("seq", (int64_t)0);
      msg.from_user_id = m.value("from_user_id", "");
      msg.to_user_id = m.value("to_user_id", "");
      msg.message_type = m.value("message_type", 0);
      msg.message_state = m.value("message_state", 0);
      msg.context_token = m.value("context_token", "");

      if (m.contains("item_list") && m["item_list"].is_array()) {
        msg.content = extract_text(&m["item_list"]);
      }

      // Cache context_token for this user
      if (!msg.context_token.empty() && !msg.from_user_id.empty()) {
        save_context_token(msg.from_user_id, msg.context_token);
      }

      msgs.push_back(std::move(msg));
    }
  } catch (const json::parse_error& e) {
    log::warn("ilink: failed to parse getupdates response: " +
              std::string(e.what()));
    return false;
  }

  return true;
}

bool IlinkHttpClient::send_message(const std::string& to_user_id,
                                    const std::string& content) {
  // Split into chunks of max 3800 chars (UTF-8 safe)
  std::vector<std::string> chunks;
  size_t offset = 0;
  while (offset < content.size()) {
    size_t len = std::min(content.size() - offset,
                          static_cast<size_t>(kMaxChunkChars));
    // Avoid splitting mid-UTF8
    while (len > 0 && offset + len < content.size()) {
      unsigned char c = static_cast<unsigned char>(content[offset + len]);
      if ((c & 0xC0) == 0x80) {
        --len;
      } else {
        break;
      }
    }
    if (len == 0) len = 1;
    chunks.push_back(content.substr(offset, len));
    offset += len;
  }

  for (size_t i = 0; i < chunks.size(); ++i) {
    // Get context_token for this user
    std::string ctx_token;
    {
      std::lock_guard<std::mutex> lock(ctx_mutex_);
      auto it = context_tokens_.find(to_user_id);
      if (it != context_tokens_.end()) ctx_token = it->second;
    }

    json msg;
    msg["msg"]["from_user_id"] = "";
    msg["msg"]["to_user_id"] = to_user_id;
    msg["msg"]["client_id"] = generate_client_id();
    msg["msg"]["message_type"] = 2;
    msg["msg"]["message_state"] = 2;
    msg["msg"]["item_list"] = json::array();
    msg["msg"]["item_list"][0]["type"] = 1;
    msg["msg"]["item_list"][0]["text_item"]["text"] = chunks[i];
    if (!ctx_token.empty()) {
      msg["msg"]["context_token"] = ctx_token;
    }
    msg["base_info"]["channel_version"] = kChannelVersion;

    bool success = false;
    for (int attempt = 0; attempt < kMaxSendRetries; ++attempt) {
      int ret_code = 0, err_code = 0;
      std::string resp_body;
      if (!do_post("/ilink/bot/sendmessage", msg.dump(),
                   ret_code, err_code, resp_body)) {
        if (attempt < kMaxSendRetries - 1) {
          std::this_thread::sleep_for(std::chrono::milliseconds(500));
          continue;
        }
        log::error("ilink: failed to send message to " + to_user_id);
        return false;
      }

      if (ret_code == -2) {
        log::warn("ilink: sendMessage ret=-2, retry " +
                  std::to_string(attempt + 1));
        std::this_thread::sleep_for(std::chrono::milliseconds(500));
        continue;
      }

      if (err_code == -14) {
        log::warn("ilink: session expired during send");
        return false;
      }

      success = true;
      break;
    }

    if (!success) {
      log::error("ilink: failed to send chunk " + std::to_string(i + 1) +
                 " to " + to_user_id + " after " +
                 std::to_string(kMaxSendRetries) + " retries");
      return false;
    }

    // Small delay between chunks
    if (i < chunks.size() - 1) {
      std::this_thread::sleep_for(std::chrono::milliseconds(100));
    }
  }

  log::info("ilink: sent " + std::to_string(chunks.size()) +
            " chunk(s) to " + to_user_id);
  return true;
}

std::string IlinkHttpClient::generate_client_id() {
  return "cc-" + random_hex(8);
}

bool IlinkHttpClient::load_cursor(std::string& cursor) {
  cursor = read_file(state_dir_ + "/get_updates.buf");
  return !cursor.empty();
}

bool IlinkHttpClient::save_cursor(const std::string& cursor) {
  return write_file(state_dir_ + "/get_updates.buf", cursor);
}

bool IlinkHttpClient::load_context_token(const std::string& user_id,
                                          std::string& token) {
  std::lock_guard<std::mutex> lock(ctx_mutex_);
  auto it = context_tokens_.find(user_id);
  if (it == context_tokens_.end()) return false;
  token = it->second;
  return true;
}

bool IlinkHttpClient::save_context_token(const std::string& user_id,
                                          const std::string& token) {
  std::lock_guard<std::mutex> lock(ctx_mutex_);
  context_tokens_[user_id] = token;
  // Persist immediately
  try {
    json j = json::object();
    for (auto& [k, v] : context_tokens_) {
      j[k] = v;
    }
    write_file(state_dir_ + "/context_tokens.json", j.dump(2));
  } catch (...) {}
  return true;
}

bool IlinkHttpClient::load_all_context_tokens() {
  std::string data = read_file(state_dir_ + "/context_tokens.json");
  if (data.empty()) return true;
  try {
    auto j = json::parse(data);
    for (auto it = j.begin(); it != j.end(); ++it) {
      context_tokens_[it.key()] = it.value().get<std::string>();
    }
    log::info("ilink: loaded " + std::to_string(context_tokens_.size()) +
              " cached context tokens");
  } catch (...) {}
  return true;
}

bool IlinkHttpClient::save_all_context_tokens() {
  try {
    json j = json::object();
    for (auto& [k, v] : context_tokens_) {
      j[k] = v;
    }
    return write_file(state_dir_ + "/context_tokens.json", j.dump(2));
  } catch (...) {}
  return false;
}

}  // namespace net
}  // namespace hiclaw
