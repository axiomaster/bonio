#pragma once

#include <string>
#include <map>
#include <algorithm>

/**
 * HarmonyOS application package name mappings.
 * Ported from reference Open-AutoGLM project.
 * 
 * Maps user-friendly app names (Chinese/English) to HarmonyOS bundle names.
 * These bundle names are used with 'aa start -b <bundle> -a <ability>' command.
 */

// Custom ability names for apps that don't use the default "EntryAbility"
inline const std::map<std::string, std::string> APP_ABILITIES = {
    // Third-party apps
    {"cn.wps.mobileoffice.hap", "DocumentAbility"},
    {"com.ccb.mobilebank.hm", "CcbMainAbility"},
    {"com.dewu.hos", "HomeAbility"},
    {"com.larus.nova.hm", "MainAbility"},
    {"com.lemon.hm.lv", "MainAbility"},  // 剪映
    {"com.luna.hm.music", "MainAbility"},
    {"com.meitu.meitupic", "MainAbility"},
    {"com.ss.hm.article.news", "MainAbility"},
    {"com.ss.hm.ugc.aweme", "MainAbility"},
    {"com.taobao.taobao4hmos", "Taobao_mainAbility"},
    {"com.tencent.videohm", "AppAbility"},
    {"com.ximalaya.ting.xmharmony", "MainBundleAbility"},
    {"com.zhihu.hmos", "PhoneAbility"},
    // Huawei system apps
    {"com.huawei.hmos.browser", "MainAbility"},
    {"com.huawei.hmos.calculator", "com.huawei.hmos.calculator.CalculatorAbility"},
    {"com.huawei.hmos.calendar", "MainAbility"},
    {"com.huawei.hmos.camera", "com.huawei.hmos.camera.MainAbility"},
    {"com.huawei.hmos.clock", "com.huawei.hmos.clock.phone"},
    {"com.huawei.hmos.clouddrive", "MainAbility"},
    {"com.huawei.hmos.email", "ApplicationAbility"},
    {"com.huawei.hmos.filemanager", "MainAbility"},
    {"com.huawei.hmos.health", "Activity_card_entryAbility"},
    {"com.huawei.hmos.notepad", "MainAbility"},
    {"com.huawei.hmos.photos", "MainAbility"},
    {"com.huawei.hmos.screenrecorder", "com.huawei.hmos.screenrecorder.ServiceExtAbility"},
    {"com.huawei.hmos.screenshot", "com.huawei.hmos.screenshot.ServiceExtAbility"},
    {"com.huawei.hmos.settings", "com.huawei.hmos.settings.MainAbility"},
    {"com.huawei.hmos.soundrecorder", "MainAbility"},
    {"com.huawei.hmos.vassistant", "AiCaptionServiceExtAbility"},
    {"com.huawei.hmos.wallet", "MainAbility"},
    // Huawei services
    {"com.huawei.hmsapp.appgallery", "MainAbility"},
    {"com.huawei.hmsapp.books", "MainAbility"},
    {"com.huawei.hmsapp.himovie", "MainAbility"},
    {"com.huawei.hmsapp.hisearch", "MainAbility"},
    {"com.huawei.hmsapp.music", "MainAbility"},
    {"com.huawei.hmsapp.thememanager", "MainAbility"},
    {"com.huawei.hmsapp.totemweather", "com.huawei.hmsapp.totemweather.MainAbility"},
    // OHOS system apps
    {"com.huawei.hmos.meetime", "MainAbility"},
    {"com.ohos.callui", "com.ohos.callui.ServiceAbility"},
    {"com.ohos.contacts", "com.ohos.contacts.MainAbility"},
    {"com.ohos.mms", "com.ohos.mms.MainAbility"},
};

// Map app names to bundle names
inline const std::map<std::string, std::string> APP_PACKAGES = {
    // Social & Messaging
    {"微信", "com.tencent.wechat"},
    {"QQ", "com.tencent.mqq"},
    {"微博", "com.sina.weibo.stage"},
    // E-commerce
    {"淘宝", "com.taobao.taobao4hmos"},
    {"京东", "com.jd.hm.mall"},
    {"拼多多", "com.xunmeng.pinduoduo.hos"},
    // Lifestyle & Social
    {"小红书", "com.xingin.xhs_hos"},
    {"知乎", "com.zhihu.hmos"},
    // Maps & Navigation
    {"高德地图", "com.amap.hmapp"},
    {"百度地图", "com.baidu.hmmap"},
    // Food & Services
    {"美团", "com.sankuai.hmeituan"},
    {"美团外卖", "com.meituan.takeaway"},
    {"大众点评", "com.sankuai.dianping"},
    // Travel
    {"铁路12306", "com.chinarailway.ticketingHM"},
    {"12306", "com.chinarailway.ticketingHM"},
    {"滴滴出行", "com.sdu.didi.hmos.psnger"},
    // Video & Entertainment
    {"bilibili", "yylx.danmaku.bili"},
    {"抖音", "com.ss.hm.ugc.aweme"},
    {"快手", "com.kuaishou.hmapp"},
    {"腾讯视频", "com.tencent.videohm"},
    {"爱奇艺", "com.qiyi.video.hmy"},
    {"芒果TV", "com.mgtv.phone"},
    {"剪映", "com.lemon.hm.lv"},
    // Music & Audio
    {"QQ音乐", "com.tencent.hm.qqmusic"},
    {"汽水音乐", "com.luna.hm.music"},
    {"喜马拉雅", "com.ximalaya.ting.xmharmony"},
    // Productivity
    {"飞书", "com.ss.feishu"},
    // AI & Tools
    {"豆包", "com.larus.nova.hm"},
    // News & Information
    {"今日头条", "com.ss.hm.article.news"},
    // HarmonyOS 第三方应用
    {"百度", "com.baidu.baiduapp"},
    {"阿里巴巴", "com.alibaba.wireless_hmos"},
    {"WPS", "cn.wps.mobileoffice.hap"},
    {"企业微信", "com.tencent.wework.hmos"},
    {"同程", "com.tongcheng.hmos"},
    {"同程旅行", "com.tongcheng.hmos"},
    {"唯品会", "com.vip.hosapp"},
    {"支付宝", "com.alipay.mobile.client"},
    {"UC浏览器", "com.uc.mobile"},
    {"闲鱼", "com.taobao.idlefish4ohos"},
    {"转转", "com.zhuanzhuan.hmoszz"},
    {"迅雷", "com.xunlei.thunder"},
    {"搜狗输入法", "com.sogou.input"},
    {"扫描全能王", "com.intsig.camscanner.hap"},
    {"美图秀秀", "com.meitu.meitupic"},
    {"58同城", "com.wuba.life"},
    {"得物", "com.dewu.hos"},
    {"海底捞", "com.haidilao.haros"},
    {"中国移动", "com.droi.tong"},
    {"中国联通", "com.sinovatech.unicom.ha"},
    {"国家税务总局", "cn.gov.chinatax.gt4.hm"},
    {"建设银行", "com.ccb.mobilebank.hm"},
    {"快手极速版", "com.kuaishou.hmnebula"},
    // HarmonyOS 系统应用 - 工具类
    {"浏览器", "com.huawei.hmos.browser"},
    {"计算器", "com.huawei.hmos.calculator"},
    {"日历", "com.huawei.hmos.calendar"},
    {"相机", "com.huawei.hmos.camera"},
    {"时钟", "com.huawei.hmos.clock"},
    {"云盘", "com.huawei.hmos.clouddrive"},
    {"云空间", "com.huawei.hmos.clouddrive"},
    {"邮件", "com.huawei.hmos.email"},
    {"文件管理器", "com.huawei.hmos.filemanager"},
    {"文件", "com.huawei.hmos.files"},
    {"查找设备", "com.huawei.hmos.finddevice"},
    {"查找手机", "com.huawei.hmos.finddevice"},
    {"录音机", "com.huawei.hmos.soundrecorder"},
    {"录音", "com.huawei.hmos.soundrecorder"},
    {"录屏", "com.huawei.hmos.screenrecorder"},
    {"截屏", "com.huawei.hmos.screenshot"},
    {"笔记", "com.huawei.hmos.notepad"},
    {"备忘录", "com.huawei.hmos.notepad"},
    // HarmonyOS 系统应用 - 媒体类
    {"相册", "com.huawei.hmos.photos"},
    {"图库", "com.huawei.hmos.photos"},
    // HarmonyOS 系统应用 - 通讯类
    {"联系人", "com.ohos.contacts"},
    {"通讯录", "com.ohos.contacts"},
    {"短信", "com.ohos.mms"},
    {"信息", "com.ohos.mms"},
    {"电话", "com.ohos.callui"},
    {"拨号", "com.ohos.callui"},
    // HarmonyOS 系统应用 - 设置类
    {"Phone", "com.huawei.hmos.contacts"},
    {"Contacts", "com.huawei.hmos.contacts"},
    {"畅连", "com.huawei.hmos.meetime"}, // Added based on user feedback
    {"Meetime", "com.huawei.hmos.meetime"}, // Alias
    {"设置", "com.huawei.hmos.settings"},
    {"系统设置", "com.huawei.hmos.settings"},
    {"Settings", "com.huawei.hmos.settings"},
    // HarmonyOS 系统应用 - 生活服务
    {"健康", "com.huawei.hmos.health"},
    {"运动健康", "com.huawei.hmos.health"},
    {"地图", "com.huawei.hmos.maps.app"},
    {"华为地图", "com.huawei.hmos.maps.app"},
    {"钱包", "com.huawei.hmos.wallet"},
    {"华为钱包", "com.huawei.hmos.wallet"},
    {"智慧生活", "com.huawei.hmos.ailife"},
    {"智能助手", "com.huawei.hmos.vassistant"},
    {"小艺", "com.huawei.hmos.vassistant"},
    // HarmonyOS 服务
    {"应用市场", "com.huawei.hmsapp.appgallery"},
    {"华为应用市场", "com.huawei.hmsapp.appgallery"},
    {"音乐", "com.huawei.hmsapp.music"},
    {"华为音乐", "com.huawei.hmsapp.music"},
    {"主题", "com.huawei.hmsapp.thememanager"},
    {"主题管理", "com.huawei.hmsapp.thememanager"},
    {"天气", "com.huawei.hmsapp.totemweather"},
    {"华为天气", "com.huawei.hmsapp.totemweather"},
    {"视频", "com.huawei.hmsapp.himovie"},
    {"华为视频", "com.huawei.hmsapp.himovie"},
    {"阅读", "com.huawei.hmsapp.books"},
    {"华为阅读", "com.huawei.hmsapp.books"},
    {"游戏中心", "com.huawei.hmsapp.gamecenter"},
    {"华为游戏中心", "com.huawei.hmsapp.gamecenter"},
    {"搜索", "com.huawei.hmsapp.hisearch"},
    {"华为搜索", "com.huawei.hmsapp.hisearch"},
    {"指南针", "com.huawei.hmsapp.compass"},
    {"会员中心", "com.huawei.hmos.myhuawei"},
    {"我的华为", "com.huawei.hmos.myhuawei"},
    {"华为会员", "com.huawei.hmos.myhuawei"},
    // 畅联 (MeeTime)
    {"畅联", "com.huawei.columbus"},
    {"MeeTime", "com.huawei.columbus"},
    {"meetime", "com.huawei.hmos.meetime"},
};

/**
 * Get the bundle name for an app display name.
 * @param app_name Display name of the app (e.g., "微信", "Settings")
 * @return Bundle name or empty string if not found
 */
inline std::string getPackageName(const std::string& app_name) {
    auto it = APP_PACKAGES.find(app_name);
    if (it != APP_PACKAGES.end()) {
        return it->second;
    }
    // If not found, assume it's already a bundle name
    if (app_name.find('.') != std::string::npos) {
        return app_name;
    }
    return "";
}

/**
 * Get the ability name for a bundle.
 * @param bundle_name Bundle name (e.g., "com.huawei.hmos.settings")
 * @return Ability name or "EntryAbility" if not found in custom mappings
 */
inline std::string getAbilityName(const std::string& bundle_name) {
    auto it = APP_ABILITIES.find(bundle_name);
    if (it != APP_ABILITIES.end()) {
        return it->second;
    }
    return "EntryAbility";
}
