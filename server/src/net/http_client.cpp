#include "hiclaw/net/http_client.hpp"
#include "hv/HttpClient.h"
#include "hv/HttpMessage.h"
#include "hv/hssl.h"
#include "hv/herr.h"
#include <cstring>
#include <iostream>
#include <string>

namespace hiclaw {
namespace net {

namespace {

std::string describe_error(int ret) {
  if (ret == -1) return "SSL error";
  if (ret == -2) return "SSL handshake: waiting for read";
  if (ret == -3) return "SSL handshake: waiting for write";
  if (ret == -4) return "SSL: would block";
  if (ret == -1041) return "failed to create SSL context";
  if (ret == -1042) return "failed to create SSL session";
  if (ret == -1043) return "SSL handshake failed";

  // libhv returns negated errno for socket errors
  int posval = (ret < 0) ? -ret : ret;
#ifdef ECONNREFUSED
  if (posval == ECONNREFUSED) return "connection refused (is the server running?)";
#endif
#ifdef EHOSTUNREACH
  if (posval == EHOSTUNREACH) return "host unreachable (network issue or server offline)";
#endif
#ifdef ENETUNREACH
  if (posval == ENETUNREACH) return "network unreachable (check WiFi/network connection)";
#endif
#ifdef ETIMEDOUT
  if (posval == ETIMEDOUT) return "connection timed out";
#endif
#ifdef ECONNRESET
  if (posval == ECONNRESET) return "connection reset by server";
#endif
#ifdef ECONNABORTED
  if (posval == ECONNABORTED) return "connection aborted";
#endif
#ifdef EPIPE
  if (posval == EPIPE) return "broken pipe (server closed connection)";
#endif

  // Try libhv's own strerror, then system strerror
  std::string hv_msg = hv_strerror(ret);
  if (!hv_msg.empty() && hv_msg != "Unknown error" && hv_msg != "Undefined error") {
    return hv_msg;
  }
  const char* sys_msg = strerror(posval);
  if (sys_msg && std::string(sys_msg).find("nknown") == std::string::npos) {
    return std::string(sys_msg) + " (code " + std::to_string(ret) + ")";
  }
  return "error code " + std::to_string(ret);
}

}  // namespace

bool post_json(const std::string& url, const std::string& body, HttpResponse& res,
               const std::string& auth_header) {
  res = HttpResponse{};

  // Debug output - show SSL backend
  const char* ssl_backend = hssl_backend();
  std::cerr << "[debug] SSL backend: " << (ssl_backend ? ssl_backend : "null") << std::endl;
  std::cerr << "[debug] HTTP POST to: " << url << std::endl;

  // Create libhv HTTP client
  hv::HttpClient cli;

  // Set timeout (60 seconds)
  cli.setTimeout(60);

  // Create request (using global ::HttpRequest from libhv)
  ::HttpRequest req;
  req.method = HTTP_POST;
  req.url = url;
  req.headers["Content-Type"] = "application/json";
  if (!auth_header.empty()) {
    req.headers["Authorization"] = auth_header;
  }
  req.body = body;
  req.timeout = 60;
  req.connect_timeout = 60;

  // Send request (using global ::HttpResponse from libhv)
  ::HttpResponse resp;
  int ret = cli.send(&req, &resp);

  if (ret != 0) {
    std::string err_str = describe_error(ret);
    std::cerr << "[debug] HTTP error code: " << ret << ", msg: " << err_str << std::endl;
    res.error = err_str;
    return false;
  }

  // Fill response
  res.status_code = resp.status_code;
  res.body = resp.body;

  std::cerr << "[debug] HTTP response status: " << res.status_code << std::endl;

  if (res.status_code < 200 || res.status_code >= 300) {
    res.error = "HTTP " + std::to_string(res.status_code);
    if (!res.body.empty()) {
      std::string preview = res.body.substr(0, 300);
      for (char& c : preview) {
        if (c == '\r' || c == '\n') c = ' ';
      }
      res.error += ": " + preview;
    }
    return false;
  }

  return true;
}

bool get(const std::string& url, HttpResponse& res) {
  res = HttpResponse{};

  // Debug output
  std::cerr << "[debug] HTTP GET to: " << url << std::endl;

  // Create libhv HTTP client
  hv::HttpClient cli;

  // Set timeout
  cli.setTimeout(60);

  // Create request (using global ::HttpRequest from libhv)
  ::HttpRequest req;
  req.method = HTTP_GET;
  req.url = url;

  // Send request (using global ::HttpResponse from libhv)
  ::HttpResponse resp;
  int ret = cli.send(&req, &resp);

  if (ret != 0) {
    std::string err_str = describe_error(ret);
    std::cerr << "[debug] HTTP error code: " << ret << ", msg: " << err_str << std::endl;
    res.error = err_str;
    return false;
  }

  // Fill response
  res.status_code = resp.status_code;
  res.body = resp.body;

  if (res.status_code < 200 || res.status_code >= 300) {
    res.error = "HTTP " + std::to_string(res.status_code);
    if (!res.body.empty()) res.error += ": " + res.body.substr(0, 200);
    return false;
  }

  return true;
}

bool post_json_streaming(const std::string& url, const std::string& body,
                         StreamCallback callback,
                         HttpResponse& res,
                         const std::string& auth_header) {
  res = HttpResponse{};

  // Debug output
  std::cerr << "[debug] HTTP POST streaming to: " << url << std::endl;

  // Create libhv HTTP client
  hv::HttpClient cli;
  cli.setTimeout(120);  // Streaming requests may take longer

  // Create request
  ::HttpRequest req;
  req.method = HTTP_POST;
  req.url = url;
  req.headers["Content-Type"] = "application/json";
  req.headers["Accept"] = "text/event-stream";
  req.headers["Cache-Control"] = "no-cache";
  if (!auth_header.empty()) {
    req.headers["Authorization"] = auth_header;
  }
  req.body = body;
  req.timeout = 120;
  req.connect_timeout = 60;

  // Response object
  ::HttpResponse resp;

  // Set up streaming callback using http_cb
  // This callback is invoked during response parsing
  req.http_cb = [&callback, &res](HttpMessage* msg, http_parser_state state, const char* data, size_t size) {
    if (state == HP_BODY && data && size > 0) {
      // Invoke the callback with the chunk
      std::string chunk(data, size);
      if (callback) {
        callback(chunk);
      }
      // Also accumulate the body
      res.body += chunk;
    }
    return 0;
  };

  // Send request
  int ret = cli.send(&req, &resp);

  if (ret != 0) {
    std::string err_str = describe_error(ret);
    std::cerr << "[debug] HTTP streaming error code: " << ret << ", msg: " << err_str << std::endl;
    res.error = err_str;
    return false;
  }

  // Fill response status
  res.status_code = resp.status_code;

  std::cerr << "[debug] HTTP streaming response status: " << res.status_code << std::endl;

  if (res.status_code < 200 || res.status_code >= 300) {
    res.error = "HTTP " + std::to_string(res.status_code);
    if (!res.body.empty()) {
      std::string preview = res.body.substr(0, 300);
      for (char& c : preview) {
        if (c == '\r' || c == '\n') c = ' ';
      }
      res.error += ": " + preview;
    }
    return false;
  }

  return true;
}

}  // namespace net
}  // namespace hiclaw
