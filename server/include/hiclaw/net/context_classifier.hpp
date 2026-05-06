#ifndef HICLAW_NET_CONTEXT_CLASSIFIER_HPP
#define HICLAW_NET_CONTEXT_CLASSIFIER_HPP

#include <nlohmann/json.hpp>
#include <string>
#include <unordered_map>
#include <vector>

namespace hiclaw {
namespace net {

/// Per-tag classification result with independent confidence.
struct TagConfidence {
  std::string tag;
  double confidence = 0.0;
};
NLOHMANN_DEFINE_TYPE_NON_INTRUSIVE(TagConfidence, tag, confidence)

/// Classifies a UI structure into content-type tags using a local Ollama model.
///
/// Tags are NOT hardcoded — the caller passes the set of available tags
/// (aggregated from installed plugin declarations), and the classifier
/// selects among them.
class ContextClassifier {
public:
  explicit ContextClassifier(const std::string& ollama_base_url,
                             const std::string& model_name);

  /// Classify a UI structure. [available_tags] comes from plugin declarations.
  /// Returns tags with independent confidence scores.
  std::vector<TagConfidence> classify(
      const nlohmann::json& ui_structure,
      const std::vector<std::string>& available_tags);

private:
  std::string classify_via_ollama(const std::string& prompt);
  std::string ollama_url_;
  std::string model_name_;
};

}  // namespace net
}  // namespace hiclaw

#endif  // HICLAW_NET_CONTEXT_CLASSIFIER_HPP
