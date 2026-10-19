'use strict';
const chinese={skip:'跳到正文',featuresNav:'功能',eyebrow:'让时间，安静地待在身边',headline:'世界此刻。<br><span>一眼尽览。</span>',intro:'多时区时钟、完整日期和当地天气。<br>Mac 桌面上，一个安静的陪伴。',download:'查看发布版本',source:'浏览 GitHub 项目',requirements:'macOS 14+ · Apple Silicon & Intel · English & 简体中文',caption:'四个地区，同一时刻。图中为示例时间与天气。',feature1Tag:'日期，一目了然',feature1Title:'跨越时区，不错过日期。',feature1:'每个时钟都显示完整年月日。前日、次日标识，让跨时区沟通更自然。日期旁的环形秒数每秒更新。',feature2Tag:'按自己的方式排列',feature2Title:'一个时钟，或你的世界。',feature2:'浏览全球 400 多个时区及代表城市，支持城市、国家搜索。最多六个时钟，可横向、纵向排列或拆开独立显示，桌面和状态栏分别选择。',feature3Tag:'再多一点当地信息',feature3Title:'也知道，那里的天气。',feature3:'天气图标和摄氏温度与时间并排显示，每15分钟更新。',storyTag:'需要时，近在眼前',storyTitle:'桌面上，自由排列。<br>状态栏里，一眼时间。',storyBody:'横向排列、纵向堆叠，或让每个时钟独立待在桌面。完整日期和时间始终在手边，点击状态栏即可展开全部地区。',storyBody2:'每个独立时钟都能拖动、吸附并记忆位置。点击布局图标切换排列；从状态栏点击“打开”恢复全部，关闭后收起到状态栏。',gettingStarted:'开始使用 Meridian',detailCaption:'需要的信息，清晰地在一起。',faqTag:'你可能想知道',faqTitle:'小细节，也照顾到了。',q1:'支持哪些语言？',a1:'默认使用英文，可以在设置中切换简体中文，无需重启应用。',q2:'天气会使用设备定位吗？',a2:'天气按每个时钟的城市从 Open-Meteo 查询，无需设备定位权限；本地时钟跟随系统时区。独立的 Mac 定位实验功能会在你点击“验证系统返回的位置”时请求定位权限。',q3:'支持自动更新吗？',a3:'已集成 Sparkle，支持自动检查和可选的后台下载。发行包会进行签名，并在安装前验证。',q4:'天气不可用时会怎样？',a4:'时钟会继续运行。无法获取或过期的天气会明确标出，也可以随时关闭天气。',closing:'让世界，离你近一点。',footer:'Mac 上，安静的一角。',footerSource:'源码与发布',q5:'可以商业使用 Meridian 吗？',a5:'Meridian 采用 PolyForm Noncommercial 1.0.0。在遵守许可证的前提下，允许许可范围内的非商业使用、修改和再分发；不授予商业使用权。',license:'非商业使用许可',weatherCredit:'天气数据 · Open-Meteo'};
Object.assign(chinese,{
  locationNav:'Mac 定位',
  heroPreview:'新功能预览 · Mac 定位 ↗',
  locationTag:'MAC 定位 · 实验版预览',
  locationTitle:'选一个地区。<br>让 Mac 定位随之切换。',
  locationIntro:'在这台 Mac 上模拟指定地区，供使用 macOS 定位服务的应用读取。',
  locationAvailability:'此功能已在 v1.5.0 实验版中提供。当前稳定版下载：<span class="stable-version">v1.4.0</span>。',
  locationSearchTitle:'查找目标城市。',
  locationSearchBody:'输入城市、州／省和国家，按回车或点击“搜索地点”。确认候选地区，也可以手动输入经纬度。',
  locationApplyTitle:'确认后，应用到 Mac。',
  locationApplyBody:'选择候选并核对坐标后再应用。macOS 会要求一次管理员授权。',
  locationVerifyTitle:'核对系统实际返回的位置。',
  locationVerifyBody:'点击“验证系统返回的位置”，读取新的 Core Location 定位，再让需要测试的应用刷新当前位置。',
  locationRestoreTitle:'用完后，恢复原定位。',
  locationRestoreBody:'点击“恢复原定位”即可恢复保存的设置。退出时可选择“恢复并退出”“保留并退出”或“取消”。',
  locationPreviewCTA:'查看实验版',
  locationGuideCTA:'使用与恢复说明',
  locationNote:'已在 macOS 27.0.1 上实测。此功能使用实验性的系统定位机制，效果可能随 macOS 版本和应用而变化。',
  locationCaption:'实验版实际界面，图中为中文。先查询和选择，再应用定位。',
  q6:'Mac 定位支持怎样的查询输入？',
  a6:'例如 Cupertino, CA - United States 或 Toronto, Ontario - Canada。城市、州／省和国家有助于区分同名地区。在线城市查询会将查询词发送给 Open-Meteo，数据来自 GeoNames，无需开启设备定位服务。也可手动输入十进制经纬度。',
  q7:'所有应用都会显示所选地区吗？',
  a7:'使用 macOS Core Location 的应用可以读取模拟地区。通过 IP、账号地区或缓存判断位置的应用，可能显示不同结果。Mac 定位不会改变你的 IP 地址或账号国家／地区。',
  q8:'退出应用会结束定位模拟吗？',
  a8:'模拟可能在退出或重启后继续生效。请点击“恢复原定位”或选择“恢复并退出”，恢复原来的模拟设置。macOS 可能再次要求管理员授权。',
  cityCredit:'城市查询 · GeoNames / Open-Meteo'
});
const nodes=[...document.querySelectorAll('[data-i18n]')];
const english=Object.fromEntries(nodes.map(n=>[n.dataset.i18n,n.innerHTML]));
let language='en';
try{language=new URLSearchParams(location.search).get('lang')||localStorage.getItem('meridian-language')||'en';}catch{}
let releaseAsset=null;
let stableVersion='v1.4.0';
function render(){const zh=language==='zh';document.documentElement.lang=zh?'zh-CN':'en';document.title=zh?'Meridian — 世界此刻，一眼尽览。':'Meridian — Your world. At a glance.';nodes.forEach(n=>{n.innerHTML=(zh?chinese:english)[n.dataset.i18n]||english[n.dataset.i18n];});const button=document.getElementById('language');button.textContent=zh?'English':'中文';button.setAttribute('aria-label',zh?'Switch to English':'切换到简体中文');document.getElementById('campaign-image').src=zh?'assets/promo-zh.png':'assets/promo-en.png';document.getElementById('location-image').alt=zh?'Meridian 实验版中文界面：查询 Cupertino, CA - United States 并选中库比蒂诺坐标':'Actual Meridian preview in Chinese, showing the Cupertino, California, United States query and selected coordinates';document.querySelectorAll('.stable-version').forEach(n=>{n.textContent=stableVersion;});if(releaseAsset){document.querySelectorAll('.download-link').forEach(n=>{n.href=releaseAsset.browser_download_url;n.textContent=zh?'下载 Mac 版':'Download for Mac';});}}
document.getElementById('language').addEventListener('click',()=>{language=language==='zh'?'en':'zh';try{localStorage.setItem('meridian-language',language);}catch{}render();});render();
fetch('https://api.github.com/repos/etongle/Meridian/releases/latest',{headers:{Accept:'application/vnd.github+json'}}).then(r=>r.ok?r.json():null).then(r=>{stableVersion=r?.tag_name||stableVersion;releaseAsset=r?.assets?.find(a=>/^Meridian-.*-macOS\.dmg$/.test(a.name))||r?.assets?.find(a=>/^Meridian-.*-macOS\.zip$/.test(a.name));if(r)render();}).catch(()=>{});
