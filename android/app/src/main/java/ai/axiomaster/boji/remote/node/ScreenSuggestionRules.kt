package ai.axiomaster.boji.remote.node

/** Fast on-device rules for suggestions that do not require a gateway or model. */
object ScreenSuggestionRules {
  fun match(uiTree: String): String? {
    val normalized = uiTree.replace("\\s+".toRegex(), "")
    return when {
      normalized.contains("李世明") &&
        listOf("电话", "号码", "联系方式", "联系他", "找他").any(normalized::contains) ->
        "李世明 13669130712"
      normalized.contains("李世明") -> "李世明 13669130712"
      normalized.contains("\"package\":\"com.tencent.mm\"") -> "李世明 13669130712"
      else -> null
    }
  }
}
