#include "hiclaw/agent/agent.hpp"
#include "hiclaw/config/config.hpp"
#include "hiclaw/net/serve.hpp"
#include "hv/HttpServer.h"
#include "hv/HttpService.h"
#include "hv/HttpMessage.h"
#include <nlohmann/json.hpp>
#include <iostream>

namespace hiclaw {
namespace net {

void serve(int port, const config::Config& config) {
  // Create HTTP service
  hv::HttpService service;

  // Register POST /run handler
  service.POST("/run", [&config](HttpRequest* req, HttpResponse* resp) {
    std::string prompt;
    try {
      nlohmann::json j = nlohmann::json::parse(req->body);
      if (j.contains("prompt") && j["prompt"].is_string())
        prompt = j["prompt"].get<std::string>();
    } catch (const nlohmann::json::parse_error&) {}

    if (prompt.empty()) {
      resp->status_code = HTTP_STATUS_BAD_REQUEST;
      resp->SetHeader("Content-Type", "application/json");
      resp->body = R"({"error":"missing prompt"})";
      return HTTP_STATUS_BAD_REQUEST;
    }

    agent::RunResult result = agent::run(config, prompt, 0.7);
    nlohmann::json out;
    if (result.ok)
      out["content"] = result.content;
    else
      out["error"] = result.error;

    resp->status_code = HTTP_STATUS_OK;
    resp->SetHeader("Content-Type", "application/json");
    resp->body = out.dump();
    return HTTP_STATUS_OK;
  });

  // Create and start server
  hv::HttpServer server(&service);
  server.setPort(port);

  std::cout << "HiClaw serve on port " << port << " (POST /run with {\"prompt\":\"...\"})\n";

  // Run server (blocking)
  server.run();
}

}  // namespace net
}  // namespace hiclaw
