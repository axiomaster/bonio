#include "hiclaw/net/context_classifier.hpp"
#include "hiclaw/observability/log.hpp"
#include <nlohmann/json.hpp>
#include <hv/HttpClient.h>
#include <sstream>

namespace hiclaw {
namespace net {

using json = nlohmann::json;

ContextClassifier::ContextClassifier(const std::string& ollama_base_url,
                                     const std::string& model_name)
    : ollama_url_(ollama_base_url), model_name_(model_name) {
  // Ensure URL ends with /v1/chat/completions if it's a base URL
  if (ollama_url_.find("/v1/chat/completions") == std::string::npos) {
    if (ollama_url_.back() != '/') ollama_url_ += '/';
    ollama_url_ += "v1/chat/completions";
  }
}

std::vector<TagConfidence> ContextClassifier::classify(
    const json& ui_structure,
    const std::vector<std::string>& available_tags) {

  if (available_tags.empty()) {
    log::warn("ContextClassifier: no available tags from plugins");
    return {};
  }

  // Build the tag description list for the prompt
  std::ostringstream tag_desc;
  for (const auto& tag : available_tags) {
    tag_desc << "- " << tag << "\n";
  }

  // Construct the classification prompt
  std::ostringstream prompt;
  prompt << "根据以下UI结构对页面进行分类。从以下标签中选择匹配的:\n"
         << tag_desc.str() << "\n"
         << "返回JSON: {\"tags\":[{\"tag\":\"标签\",\"confidence\":0.95}]}\n"
         << "每个标签confidence独立打分。>0.7可主动推荐, 0.3-0.7仅排序, <0.3忽略。\n"
         << "只返回JSON，不要包含其他内容。\n\n"
         << "UI结构: " << ui_structure.dump();

  const std::string response = classify_via_ollama(prompt.str());
  if (response.empty()) {
    log::warn("ContextClassifier: empty response from Ollama");
    return {};
  }

  // Parse the JSON response
  try {
    auto resp = json::parse(response);
    std::vector<TagConfidence> result;

    // Handle both response formats:
    // 1. OpenAI-compatible: {"choices":[{"message":{"content":"{\"tags\":[...]}"}}]}
    // 2. Direct: {"tags":[...]}
    json tags_json;
    if (resp.contains("choices") && resp["choices"].is_array() &&
        !resp["choices"].empty()) {
      const auto& choice = resp["choices"][0];
      if (choice.contains("message") && choice["message"].contains("content")) {
        std::string content = choice["message"]["content"];
        tags_json = json::parse(content);
      }
    } else if (resp.contains("tags")) {
      tags_json = resp;
    }

    if (tags_json.contains("tags") && tags_json["tags"].is_array()) {
      for (const auto& t : tags_json["tags"]) {
        TagConfidence tc;
        tc.tag = t.value("tag", "");
        tc.confidence = t.value("confidence", 0.0);
        if (!tc.tag.empty() && tc.confidence >= 0.3) {
          result.push_back(tc);
        }
      }
    }
    return result;
  } catch (const std::exception& e) {
    log::warn(std::string("ContextClassifier: parse error: ") + e.what());
    return {};
  }
}

std::string ContextClassifier::classify_via_ollama(const std::string& prompt) {
  try {
    json body;
    body["model"] = model_name_;
    body["messages"] = json::array();
    body["messages"].push_back({
        {"role", "user"},
        {"content", prompt}
    });
    body["stream"] = false;
    body["options"] = {{"temperature", 0.1}};

    log::info("ContextClassifier: sending to Ollama, prompt_len=" +
              std::to_string(prompt.size()));

    hv::HttpClient cli;
    cli.setTimeout(10); // 10s timeout

    ::HttpRequest req;
    req.method = HTTP_POST;
    req.url = ollama_url_;
    req.headers["Content-Type"] = "application/json";
    req.body = body.dump();

    ::HttpResponse resp;
    int ret = cli.send(&req, &resp);
    if (ret != 0) {
      log::warn("ContextClassifier: HTTP error " + std::to_string(ret));
      return "";
    }

    if (resp.status_code != 200) {
      log::warn("ContextClassifier: HTTP " + std::to_string(resp.status_code) +
                " body=" + resp.body.substr(0, 500));
      return "";
    }

    return resp.body;
  } catch (const std::exception& e) {
    log::warn(std::string("ContextClassifier: request error: ") + e.what());
    return "";
  }
}

}  // namespace net
}  // namespace hiclaw
