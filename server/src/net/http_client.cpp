#include "hiclaw/net/http_client.hpp"
#include "hv/HttpClient.h"
#include "hv/HttpMessage.h"
#include "hv/hssl.h"
#include "hv/herr.h"
#include <iostream>
#include <string>

namespace hiclaw {
namespace net {

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
    std::string err_str;
    // Handle SSL-specific error codes from hssl.h
    if (ret == -1) {
      err_str = "HSSL_ERROR";
    } else if (ret == -2) {
      err_str = "HSSL_WANT_READ (SSL handshake needs more data to read)";
    } else if (ret == -3) {
      err_str = "HSSL_WANT_WRITE (SSL handshake needs to write more data)";
    } else if (ret == -4) {
      err_str = "HSSL_WOULD_BLOCK";
    } else if (ret == -1041) {
      err_str = "ERR_NEW_SSL_CTX (failed to create SSL context)";
    } else if (ret == -1042) {
      err_str = "ERR_NEW_SSL (failed to create SSL session)";
    } else if (ret == -1043) {
      err_str = "ERR_SSL_HANDSHAKE (SSL handshake failed)";
    } else {
      // Try hv_strerror for other error codes
      err_str = hv_strerror(ret);
      if (err_str.empty() || err_str == "Unknown error") {
        err_str = "error code " + std::to_string(ret);
      }
    }
    std::cerr << "[debug] HTTP error code: " << ret << ", msg: " << err_str << std::endl;
    res.error = "HTTP request failed: " + err_str;
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
    std::string err_str = hv_strerror(ret);
    std::cerr << "[debug] HTTP error code: " << ret << ", msg: " << err_str << std::endl;
    res.error = "HTTP request failed (code=" + std::to_string(ret) + "): " + err_str;
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
    std::string err_str;
    if (ret == -1) {
      err_str = "HSSL_ERROR";
    } else if (ret == -2) {
      err_str = "HSSL_WANT_READ";
    } else if (ret == -3) {
      err_str = "HSSL_WANT_WRITE";
    } else if (ret == -4) {
      err_str = "HSSL_WOULD_BLOCK";
    } else if (ret == -1041) {
      err_str = "ERR_NEW_SSL_CTX";
    } else if (ret == -1042) {
      err_str = "ERR_NEW_SSL";
    } else if (ret == -1043) {
      err_str = "ERR_SSL_HANDSHAKE";
    } else {
      err_str = hv_strerror(ret);
      if (err_str.empty() || err_str == "Unknown error") {
        err_str = "error code " + std::to_string(ret);
      }
    }
    std::cerr << "[debug] HTTP streaming error code: " << ret << ", msg: " << err_str << std::endl;
    res.error = "HTTP request failed: " + err_str;
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
