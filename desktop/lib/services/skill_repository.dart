import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/skill_models.dart';
import 'gateway_session.dart';

class SkillRepository {
  final GatewaySession session;

  SkillRepository(this.session);

  Future<List<SkillInfo>> listSkills() async {
    try {
      final raw = await session.request('skills.list', null);
      debugPrint('SkillRepository: skills.list: $raw');
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final skills = json['skills'] as List<dynamic>? ?? [];
      return skills
          .map((e) => SkillInfo.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('SkillRepository: skills.list failed: $e');
      rethrow;
    }
  }

  Future<bool> enableSkill(String id) async {
    try {
      final params = jsonEncode({'id': id});
      final raw = await session.request('skills.enable', params);
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return json['enabled'] as bool? ?? true;
    } catch (e) {
      debugPrint('SkillRepository: skills.enable failed: $e');
      rethrow;
    }
  }

  Future<bool> disableSkill(String id) async {
    try {
      final params = jsonEncode({'id': id});
      final raw = await session.request('skills.disable', params);
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return !(json['enabled'] as bool? ?? false);
    } catch (e) {
      debugPrint('SkillRepository: skills.disable failed: $e');
      rethrow;
    }
  }

  Future<bool> installSkill(String id, String content) async {
    try {
      final params = jsonEncode({'id': id, 'content': content});
      await session.request('skills.install', params);
      return true;
    } catch (e) {
      debugPrint('SkillRepository: skills.install failed: $e');
      rethrow;
    }
  }

  Future<bool> removeSkill(String id) async {
    try {
      final params = jsonEncode({'id': id});
      await session.request('skills.remove', params);
      return true;
    } catch (e) {
      debugPrint('SkillRepository: skills.remove failed: $e');
      rethrow;
    }
  }
}
