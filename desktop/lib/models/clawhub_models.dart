class ClawHubSearchResult {
  final String slug;
  final String displayName;
  final String summary;
  final double score;
  final int updatedAt;

  const ClawHubSearchResult({
    this.slug = '',
    this.displayName = '',
    this.summary = '',
    this.score = 0,
    this.updatedAt = 0,
  });

  factory ClawHubSearchResult.fromJson(Map<String, dynamic> json) =>
      ClawHubSearchResult(
        slug: json['slug'] as String? ?? '',
        displayName: json['displayName'] as String? ?? '',
        summary: json['summary'] as String? ?? '',
        score: (json['score'] as num?)?.toDouble() ?? 0,
        updatedAt: json['updatedAt'] as int? ?? 0,
      );
}

class ClawHubOwner {
  final String handle;
  final String displayName;
  final String? image;

  const ClawHubOwner({
    this.handle = '',
    this.displayName = '',
    this.image,
  });

  factory ClawHubOwner.fromJson(Map<String, dynamic> json) => ClawHubOwner(
        handle: json['handle'] as String? ?? '',
        displayName: json['displayName'] as String? ?? '',
        image: json['image'] as String?,
      );
}

class ClawHubStats {
  final int stars;
  final int downloads;
  final int installsAllTime;
  final int installsCurrent;
  final int comments;
  final int versions;

  const ClawHubStats({
    this.stars = 0,
    this.downloads = 0,
    this.installsAllTime = 0,
    this.installsCurrent = 0,
    this.comments = 0,
    this.versions = 0,
  });

  factory ClawHubStats.fromJson(Map<String, dynamic> json) => ClawHubStats(
        stars: json['stars'] as int? ?? 0,
        downloads: json['downloads'] as int? ?? 0,
        installsAllTime: json['installsAllTime'] as int? ?? 0,
        installsCurrent: json['installsCurrent'] as int? ?? 0,
        comments: json['comments'] as int? ?? 0,
        versions: json['versions'] as int? ?? 0,
      );
}

class ClawHubVersion {
  final String version;
  final int createdAt;
  final String? changelog;

  const ClawHubVersion({
    this.version = '',
    this.createdAt = 0,
    this.changelog,
  });

  factory ClawHubVersion.fromJson(Map<String, dynamic> json) =>
      ClawHubVersion(
        version: json['version'] as String? ?? '',
        createdAt: json['createdAt'] as int? ?? 0,
        changelog: json['changelog'] as String?,
      );
}

class ClawHubSkillPayload {
  final String slug;
  final String displayName;
  final String summary;
  final ClawHubStats stats;
  final Map<String, String> tags;

  const ClawHubSkillPayload({
    this.slug = '',
    this.displayName = '',
    this.summary = '',
    this.stats = const ClawHubStats(),
    this.tags = const {},
  });

  factory ClawHubSkillPayload.fromJson(Map<String, dynamic> json) =>
      ClawHubSkillPayload(
        slug: json['slug'] as String? ?? '',
        displayName: json['displayName'] as String? ?? '',
        summary: json['summary'] as String? ?? '',
        stats: json['stats'] != null
            ? ClawHubStats.fromJson(json['stats'] as Map<String, dynamic>)
            : const ClawHubStats(),
        tags: (json['tags'] as Map<String, dynamic>?)
                ?.map((k, v) => MapEntry(k, v.toString())) ??
            const {},
      );
}

class ClawHubSkillDetail {
  final ClawHubSkillPayload skill;
  final ClawHubVersion? latestVersion;
  final ClawHubOwner owner;

  const ClawHubSkillDetail({
    this.skill = const ClawHubSkillPayload(),
    this.latestVersion,
    this.owner = const ClawHubOwner(),
  });

  factory ClawHubSkillDetail.fromJson(Map<String, dynamic> json) =>
      ClawHubSkillDetail(
        skill: json['skill'] != null
            ? ClawHubSkillPayload.fromJson(
                json['skill'] as Map<String, dynamic>)
            : const ClawHubSkillPayload(),
        latestVersion: json['latestVersion'] != null
            ? ClawHubVersion.fromJson(
                json['latestVersion'] as Map<String, dynamic>)
            : null,
        owner: json['owner'] != null
            ? ClawHubOwner.fromJson(json['owner'] as Map<String, dynamic>)
            : const ClawHubOwner(),
      );
}
