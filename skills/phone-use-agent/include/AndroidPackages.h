#pragma once

#include <string>
#include <map>
#include <algorithm>

/**
 * Android application package name mappings.
 * Ported from reference Open-AutoGLM project.
 *
 * Maps user-friendly app names (Chinese/English) to Android package names.
 * These package names are used with 'am start -n <package>/<activity>' command.
 */

// Map app names to Android package names
inline const std::map<std::string, std::string> ANDROID_PACKAGES = {
    // Social & Messaging
    {"微信", "com.tencent.mm"},
    {"WeChat", "com.tencent.mm"},
    {"wechat", "com.tencent.mm"},
    {"QQ", "com.tencent.mobileqq"},
    {"微博", "com.sina.weibo"},
    {"Telegram", "org.telegram.messenger"},
    {"Whatsapp", "com.whatsapp"},
    {"WhatsApp", "com.whatsapp"},
    {"Twitter", "com.twitter.android"},
    {"twitter", "com.twitter.android"},
    {"X", "com.twitter.android"},

    // E-commerce
    {"淘宝", "com.taobao.taobao"},
    {"淘宝闪购", "com.taobao.taobao"},
    {"京东", "com.jingdong.app.mall"},
    {"京东秒送", "com.jingdong.app.mall"},
    {"拼多多", "com.xunmeng.pinduoduo"},
    {"小红书", "com.xingin.xhs"},
    {"temu", "com.einnovation.temu"},
    {"Temu", "com.einnovation.temu"},

    // Lifestyle & Social
    {"豆瓣", "com.douban.frodo"},
    {"知乎", "com.zhihu.android"},

    // Maps & Navigation
    {"高德地图", "com.autonavi.minimap"},
    {"百度地图", "com.baidu.BaiduMap"},
    {"Google Maps", "com.google.android.apps.maps"},
    {"GoogleMaps", "com.google.android.apps.maps"},
    {"googlemaps", "com.google.android.apps.maps"},
    {"Osmand", "net.osmand"},
    {"osmand", "net.osmand"},

    // Food & Services
    {"美团", "com.sankuai.meituan"},
    {"大众点评", "com.dianping.v1"},
    {"饿了么", "me.ele"},
    {"肯德基", "com.yek.android.kfc.activitys"},
    {"McDonald", "com.mcdonalds.app"},
    {"mcdonald", "com.mcdonalds.app"},

    // Travel
    {"携程", "ctrip.android.view"},
    {"铁路12306", "com.MobileTicket"},
    {"12306", "com.MobileTicket"},
    {"去哪儿", "com.Qunar"},
    {"去哪儿旅行", "com.Qunar"},
    {"滴滴出行", "com.sdu.didi.psnger"},
    {"Booking.com", "com.booking"},
    {"Booking", "com.booking"},
    {"booking.com", "com.booking"},
    {"booking", "com.booking"},
    {"Expedia", "com.expedia.bookings"},
    {"expedia", "com.expedia.bookings"},

    // Video & Entertainment
    {"bilibili", "tv.danmaku.bili"},
    {"抖音", "com.ss.android.ugc.aweme"},
    {"Tiktok", "com.zhiliaoapp.musically"},
    {"tiktok", "com.zhiliaoapp.musically"},
    {"快手", "com.smile.gifmaker"},
    {"腾讯视频", "com.tencent.qqlive"},
    {"爱奇艺", "com.qiyi.video"},
    {"优酷视频", "com.youku.phone"},
    {"芒果TV", "com.hunantv.imgo.activity"},
    {"红果短剧", "com.phoenix.read"},
    {"VLC", "org.videolan.vlc"},

    // Music & Audio
    {"网易云音乐", "com.netease.cloudmusic"},
    {"QQ音乐", "com.tencent.qqmusic"},
    {"汽水音乐", "com.luna.music"},
    {"喜马拉雅", "com.ximalaya.ting.android"},

    // Reading
    {"番茄小说", "com.dragon.read"},
    {"番茄免费小说", "com.dragon.read"},
    {"七猫免费小说", "com.kmxs.reader"},

    // Productivity
    {"飞书", "com.ss.android.lark"},
    {"QQ邮箱", "com.tencent.androidqqmail"},
    {"Joplin", "net.cozic.joplin"},
    {"joplin", "net.cozic.joplin"},

    // AI & Tools
    {"豆包", "com.larus.nova"},
    {"Chrome", "com.android.chrome"},
    {"chrome", "com.android.chrome"},
    {"Google Chrome", "com.android.chrome"},

    // Health & Fitness
    {"keep", "com.gotokeep.keep"},
    {"美柚", "com.lingan.seeyou"},

    // News & Information
    {"腾讯新闻", "com.tencent.news"},
    {"今日头条", "com.ss.android.article.news"},
    {"Quora", "com.quora.android"},
    {"quora", "com.quora.android"},
    {"Reddit", "com.reddit.frontpage"},
    {"reddit", "com.reddit.frontpage"},

    // Real Estate
    {"贝壳找房", "com.lianjia.beike"},
    {"安居客", "com.anjuke.android.app"},

    // Finance
    {"同花顺", "com.hexin.plat.android"},

    // Games
    {"星穹铁道", "com.miHoYo.hkrpg"},
    {"崩坏：星穹铁道", "com.miHoYo.hkrpg"},
    {"恋与深空", "com.papegames.lysk.cn"},

    // Google Apps
    {"gmail", "com.google.android.gm"},
    {"Gmail", "com.google.android.gm"},
    {"GoogleMail", "com.google.android.gm"},
    {"Google Drive", "com.google.android.apps.docs"},
    {"GoogleDrive", "com.google.android.apps.docs"},
    {"Googledrive", "com.google.android.apps.docs"},
    {"googledrive", "com.google.android.apps.docs"},
    {"Google Docs", "com.google.android.apps.docs.editors.docs"},
    {"GoogleDocs", "com.google.android.apps.docs.editors.docs"},
    {"googledocs", "com.google.android.apps.docs.editors.docs"},
    {"Google Slides", "com.google.android.apps.docs.editors.slides"},
    {"GoogleSlides", "com.google.android.apps.docs.editors.slides"},
    {"Google Calendar", "com.google.android.calendar"},
    {"GoogleCalendar", "com.google.android.calendar"},
    {"Google Contacts", "com.google.android.contacts"},
    {"GoogleContacts", "com.google.android.contacts"},
    {"Google Keep", "com.google.android.keep"},
    {"GoogleKeep", "com.google.android.keep"},
    {"googlekeep", "com.google.android.keep"},
    {"Google Tasks", "com.google.android.apps.tasks"},
    {"GoogleTasks", "com.google.android.apps.tasks"},
    {"Google Chat", "com.google.android.apps.dynamite"},
    {"GoogleChat", "com.google.android.apps.dynamite"},
    {"Google Fit", "com.google.android.apps.fitness"},
    {"GoogleFit", "com.google.android.apps.fitness"},
    {"googlefit", "com.google.android.apps.fitness"},
    {"Google Play Store", "com.android.vending"},
    {"GooglePlayStore", "com.android.vending"},
    {"Google Play Books", "com.google.android.apps.books"},
    {"GooglePlayBooks", "com.google.android.apps.books"},
    {"GoogleFiles", "com.google.android.apps.nbu.files"},
    {"Google Files", "com.google.android.apps.nbu.files"},

    // Android System Apps
    {"AndroidSystemSettings", "com.android.settings"},
    {"Android System Settings", "com.android.settings"},
    {"Settings", "com.android.settings"},
    {"Clock", "com.android.deskclock"},
    {"clock", "com.android.deskclock"},
    {"Contacts", "com.android.contacts"},
    {"contacts", "com.android.contacts"},
    {"Files", "com.android.fileexplorer"},
    {"files", "com.android.fileexplorer"},
    {"File Manager", "com.android.fileexplorer"},
    {"AudioRecorder", "com.android.soundrecorder"},
    {"audiorecorder", "com.android.soundrecorder"},

    // Other Apps
    {"Bluecoins", "com.rammigsoftware.bluecoins"},
    {"bluecoins", "com.rammigsoftware.bluecoins"},
    {"Broccoli", "com.flauschcode.broccoli"},
    {"broccoli", "com.flauschcode.broccoli"},
    {"Duolingo", "com.duolingo"},
    {"duolingo", "com.duolingo"},
    {"PiMusicPlayer", "com.Project100Pi.themusicplayer"},
    {"pimusicplayer", "com.Project100Pi.themusicplayer"},
    {"RetroMusic", "code.name.monkey.retromusic"},
    {"retromusic", "code.name.monkey.retromusic"},
    {"SimpleCalendarPro", "com.scientificcalculatorplus.simplecalculator.basiccalculator.mathcalc"},
    {"SimpleSMSMessenger", "com.simplemobiletools.smsmessenger"},
};

// Main activities for Android apps (when not using default)
inline const std::map<std::string, std::string> ANDROID_ACTIVITIES = {
    // Most apps use .MainActivity or similar, add custom ones here
    {"com.tencent.mm", "com.tencent.mm.ui.LauncherUI"},
    {"com.taobao.taobao", "com.taobao.tao.TBMainActivity"},
    {"com.jingdong.app.mall", "com.jingdong.app.mall.MainFrameActivity"},
};

/**
 * Get the Android package name for an app display name.
 * @param app_name Display name of the app (e.g., "微信", "WeChat")
 * @return Package name or empty string if not found
 */
inline std::string getAndroidPackageName(const std::string& app_name) {
    auto it = ANDROID_PACKAGES.find(app_name);
    if (it != ANDROID_PACKAGES.end()) {
        return it->second;
    }
    // If not found, assume it's already a package name
    if (app_name.find('.') != std::string::npos) {
        return app_name;
    }
    return "";
}

/**
 * Get the main activity for an Android package.
 * @param package_name Package name (e.g., "com.tencent.mm")
 * @return Activity name (e.g., "com.tencent.mm.ui.LauncherUI") or empty for default
 */
inline std::string getAndroidActivity(const std::string& package_name) {
    auto it = ANDROID_ACTIVITIES.find(package_name);
    if (it != ANDROID_ACTIVITIES.end()) {
        return it->second;
    }
    return "";  // Empty means use monkey to launch
}
