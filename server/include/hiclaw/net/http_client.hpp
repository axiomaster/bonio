#ifndef HICLAW_NET_HTTP_CLIENT_HPP
#define HICLAW_NET_HTTP_CLIENT_HPP

#include <string>
#include <functional>

namespace hiclaw {
namespace net {

struct HttpResponse {
  int status_code = 0;
  std::string body;
  std::string error;
};

/**
 * POST to url with JSON body. Supports HTTP and HTTPS (HTTPS via mbedTLS, libhv).
 * auth_header: optional e.g. "Bearer sk-xxx" (empty = no auth).
 */
bool post_json(const std::string& url, const std::string& body, HttpResponse& res,
               const std::string& auth_header = "");

/**
 * GET url. Supports HTTP and HTTPS. Returns response body in res.body.
 */
bool get(const std::string& url, HttpResponse& res);

/**
 * Stream callback type: called for each chunk of data received.
 * Used for SSE (Server-Sent Events) streaming responses.
 */
using StreamCallback = std::function<void(const std::string& /*chunk*/)>;

/**
 * Streaming POST JSON for SSE responses.
 * The callback is invoked for each chunk of data received.
 * Returns true if the request was successful (HTTP 2xx).
 * The full response body is accumulated in res.body for reference.
 */
bool post_json_streaming(const std::string& url, const std::string& body,
                         StreamCallback callback,
                         HttpResponse& res,
                         const std::string& auth_header = "");

}  // namespace net
}  // namespace hiclaw

#endif
