# 图像资产台账（数据来源与版权自查依据）

> 路线（**2026-10-03 定稿**）：**AI 生成图仅限首页年代块 6 张**（`EraTheme.ERA_COVER_IMAGES` 白名单，挂「示意图」角标）；
> **其余一切图位一律使用真实照片**（自有拍摄或已授权图），未到位前按制式回退：遗址 = 年代色整块「图像整备中」，文物 = 单色剪影。
> 真实照片命名约定：**`real_` 前缀**（如 `images/qingtai/real_sizhipin.webp`，符合 schema pattern），UI 仅渲染 `real_` 图（判定逻辑在 `common/ImagePolicy.ets`）。
> 仓内既有 AI 图（113 遗址级 + 104 文物级引用）保留在盘与 JSON 中作为占位素材库与拍摄清单参照，但除首页 6 张外不再上屏。
> 落盘规范：`resources/rawfile/images/<遗址>/<名称>.webp`，宽 1024、quality 78、约 150KB 以内，文件名必须与 sites JSON 引用完全一致。

## 状态表·第一批（原 9 条：遗址级 29 张引用；文物级 26 张引用在 relics[].images，全部待真实照片）

| 路径 | 内容 | 来源 | 状态 |
|---|---|---|---|
| images/dongjing/zhouqiao_qiaoti.webp | 州桥及汴河桥体发掘 | AI 示意图 | ✅ 已入仓 2026-09-22 |
| images/dongjing/bimian_shike_haima.webp | 北宋壁面石刻马 | AI 示意图 | ✅ 已入仓 |
| images/dongjing/bianhe_daoyi_jiegou.webp | 汴河道遗迹剖面 | AI 示意图 | ✅ 已入仓 |
| images/erlitou/gongcheng_jianzhuji.webp | 宫城建筑基址 | AI 示意图 | ✅ 已入仓 |
| images/erlitou/xiadu_bowuguan.webp | 夏都博物馆外观 | AI 示意图 | ✅ 已入仓 |
| images/erlitou/tongjue_rudingwen.webp | 乳钉纹铜爵 | 真实照片 | ⏳ 待（二里头博物馆公开图） |
| images/erlitou/lvsongshi_tongpaishi.webp | 绿松石铜牌饰 | 真实照片 | ⏳ 待 |
| images/hanwei_luoyangcheng/changhe_men.webp | 阊阖门遗址 | AI 示意图 | ✅ 已入仓 |
| images/hanwei_luoyangcheng/yongning_si_taji.webp | 永宁寺塔基 | AI 示意图 | ✅ 已入仓 |
| images/hanwei_luoyangcheng/tongtuo_jie_zuobiao.webp | 铜驼街道路遗迹 | AI 示意图 | ✅ 已入仓 |
| images/suoyang/muzang_qingjing.webp | 仰韶墓地发掘全景 | AI 示意图 | ⛔ 待生成（配额，提示词见下） |
| images/suoyang/yuqi_hengjue.webp | 玉戚/衡诀类玉器 | 真实照片 | ⏳ 待 |
| images/suoyang/caise_taowenguan.webp | 彩陶瓮棺 | 真实照片 | ⏳ 待 |
| images/wangchenggang/chengqiang_hangtu.webp | 龙山城墙夯土 | AI 示意图 | ⛔ 待生成 |
| images/wangchenggang/longshan_heitao.webp | 龙山黑陶 | 真实照片 | ⏳ 待 |
| images/wangchenggang/qingtong_qixingpian.webp | 青铜七星片 | 真实照片 | ⏳ 待 |
| images/xishuipo/bengsu_longhu_m45.webp | 蚌塑龙虎 M45 | 真实照片 | ⏳ 待（濮院/博物馆名场面，禁 AI） |
| images/xishuipo/ertongfen_muzang.webp | 儿童瓮棺葬 | AI 示意图 | ⛔ 待生成 |
| images/xishuipo/zuji_a.webp | 足迹遗迹 A | 真实照片 | ⏳ 待 |
| images/yangshao_village/yangshao_bowuguan.webp | 仰韶村博物馆 | AI 示意图 | ⛔ 待生成 |
| images/yangshao_village/caitaopen.webp | 彩陶盆 | 真实照片 | ⏳ 待 |
| images/yangshao_village/xiaokou_jiandiping.webp | 小口尖底瓶 | 真实照片 | ⏳ 待 |
| images/yanshi_shangcheng/gongcheng_yiji.webp | 宫城遗址 | AI 示意图 | ⛔ 待生成 |
| images/yanshi_shangcheng/shiqi_shuidao.webp | 石砌水道 | AI 示意图 | ⛔ 待生成 |
| images/yanshi_shangcheng/taoci_liqi.webp | 陶瓷礼器 | 真实照片 | ⏳ 待 |
| images/zhengzhou_shangcheng/chengqiang_hangtu.webp | 商城城墙夯土 | AI 示意图 | ⛔ 待生成 |
| images/zhengzhou_shangcheng/shangdu_yuanbowuyuan.webp | 商都遗址博物馆 | AI 示意图 | ⛔ 待生成 |
| images/zhengzhou_shangcheng/duling_fangding.webp | 杜岭方鼎 | 真实照片 | ⏳ 待（国博/豫博公开图） |
| images/zhengzhou_shangcheng/niushou_zun.webp | 兽面纹尊 | 真实照片 | ⏳ 待 |

统计：AI 示意图 16 = ✅8 + ⛔8（生图 API 配额 403 受限，恢复后按下方提示词补）；真实照片待补 15（遗址级）+ 文物级若干。

## 状态表·第二批（2026-10-01 新增 33 条遗址，共 42 条语料）

> 第二批遗址级图全部为 ⛔ 待生成 AI 示意图（景观/遗址/展馆类，禁含可读文字与人物）；
> 文物级引用（列在"数量"的 +n 中，即 relics[].images）一律真实照片路线 ⏳，未到齐前 UI 走年代色占位。
> 提示词尚未逐条编写——生成前先按第一批 8 条的模板逐遗址补写并在此登记。

| 遗址 id | 名称 | images/ 下引用文件名（前缀 images/<id>/，.webp） | 数量 遗址级+文物级 | 状态 |
|---|---|---|---|---|
| bancun | 班村遗址 | fangji_huikeng taopian_lei | 2+2 | ⛔+⏳ |
| dahecun | 大河村遗址 | fangji_caifeng lingzhi_biaoshi taoyao_yiji | 3+3 | ⛔+⏳ |
| diqiu | 帝丘遗址（濮阳卫国都邑层） | wa_yi_lei jucun_bei_cankao | 2+2 | ⛔+⏳ |
| dongzhou_wangcheng | 东周王城遗址 | chengqu_hangtu tianzijia_liu cangge_jianzhi | 3+3 | ⛔+⏳ |
| duling_fangding | 商代杜岭方鼎（郑州商城出土） | duling_fangding_da shoumian_wen_tuo chutu_keng_yuanzhu | 3+2 | ⛔+⏳ |
| gongxian_yao | 巩义窑址 | yaoke_fajian_xielie sancai_shou baici_guan | 3+3 | ⛔+⏳ |
| guo_group_cemetery | 上村岭虢国墓地 | chema_keng muzang_jieshao bowuguan_chenti | 3+3 | ⛔+⏳ |
| han_tongguan | 潼关故城 | guanmen_yizhi chengqu_faxian huanghe_guandu | 3+2 | ⛔+⏳ |
| hanwei_luoyangcheng_taiji | 汉魏洛阳城太极殿遗址 | taiji_dian_ji gongmen_yujing huilang_jiegou | 3+3 | ⛔+⏳ |
| huanghe_gendi | 黄河濮阳段明清堤防与古渡遗存 | di_ba_cankao du_kou_yizhi | 2+2 | ⛔+⏳ |
| huatigou | 开封黄河河堤口遗址 | di_ceng_jie lushu_cankao | 2+2 | ⛔+⏳ |
| jingjiugong | 宋东京宫城与内城遗址 | zhouqiao_bibi luocheng_hangtu_cankao yujie_jiegou | 3+3 | ⛔+⏳ |
| kaifeng_longshan | 开封龙山时代聚落群（聚合档案） | heibian_gaojing_bei gutui_drilling_zh | 2+2 | ⛔+⏳ |
| kaifeng_xian | 开封先民聚落遗存（仰韶时期聚合档案） | pucha_caotao_pian huikeng_cigong | 2+2 | ⛔+⏳ |
| kaita | 开封铁塔（祐国寺塔） | tieta_quanmao liuli_zhuan_shi taxin_jiejin | 3+2 | ⛔+⏳ |
| kuo_state_city | 郐国故城 | chengyuan_hangtu chengmen_kouque jicheng_waibian | 3+2 | ⛔+⏳ |
| mianchi_yangshao | 渑池仰韶文化遗址群（窑址·聚落聚合档案） | jieditai_zhi caitao_pian | 2+2 | ⛔+⏳ |
| miaodigou | 庙底沟遗址 | huabanwen_caitao fangji_jiugeng bowuguan_waiguan | 3+3 | ⛔+⏳ |
| puyang_xian | 濮阳先民聚落遗存（仰韶—龙山聚合档案） | gutui_hangtu heitao_lei | 2+2 | ⛔+⏳ |
| qicheng | 戚城遗址 | chengqiang_duan taopian_caiji jingqu_gaihuang | 3+2 | ⛔+⏳ |
| qifeng_gucheng | 启封故城 | hangtu_wadang qikai_quan | 2+2 | ⛔+⏳ |
| qiji | 尉氏邱集遗址 | heitaolei_cankao shi_nongju | 2+2 | ⛔+⏳ |
| qingtai | 青台遗址 | huanhao_jubu sik_yajia_can taopian_zonghe | 3+3 | ⛔+⏳ |
| shaogong_ling | 邵公垒（东周王陵大冢群） | zhong_qun_yuanjing biaozhi_bei | 2+2 | ⛔+⏳ |
| song_ling | 北宋皇陵（永昭陵等） | shike_yiwei lingtai_gaihuang yongzhao_gongyuan | 3+2 | ⛔+⏳ |
| tiejun_miao | 铁枪庙遗址（宋澶州故城层） | miao_jian_zhu song_ceng_cankao | 2+2 | ⛔+⏳ |
| wanwang_wangwan | 王湾遗址 | fazhi_huikeng_z taqi_xilie | 2+2 | ⛔+⏳ |
| xiaoshuangqiao | 小双桥遗址 | jisi_keng_cankao qingtong_goujian taopian_duidun | 3+3 | ⛔+⏳ |
| xingyang_gucheng | 荥阳故城 | chengyuan_duan yetie_fangyi_cankao wangba_tai | 3+3 | ⛔+⏳ |
| xinzhai | 新砦遗址 | cheng_hao_jubu zhu_qun_yi | 2+3 | ⛔+⏳ |
| xizhucun_caozhong_m | 西朱村曹魏墓 | mudi_jiekou famu_jieshao shipai_xilie | 3+3 | ⛔+⏳ |
| yanshi | 偃师（古偃师城聚落层） | han_jing_yi_cankao shouyang_shan | 2+2 | ⛔+⏳ |
| zhou_gucheng | 汴州故城（先秦至唐汴州城） | daliang_jieshi_cankao tang_lushu_cankao kai_chengqiang | 3+2 | ⛔+⏳ |

统计（第二批）：遗址级 84 张 AI 示意图待生成；文物级 78 张真实照片待补。全库合计：遗址级 113、文物级 104。

## 待生成 8 张的提示词（恢复配额后直接用；统一 1792x1024，转 webp 命令见下）

1. **suoyang/muzang_qingjing** — Neolithic Yangshao-culture cemetery excavation scene on the Yellow River loess plain, China: rows of rectangular earthen pit graves at different depths, a few painted pottery jars placed in situ, brush-cleared section walls, grid strings, distant loess hills, gentle morning light, respectful scientific documentary photography, no human remains shown, no people, no text, no watermark
2. **wangchenggang/chengqiang_hangtu** — Rammed-earth city wall remnant of a Longshan-culture walled settlement between the Yi and Luo rivers, Henan, China: eroded ochre earthen ridge with visible horizontal ramming-layer sections, wheat fields at its foot, overcast soft light, documentary archaeology photography, no people, no text, no watermark
3. **xishuipo/ertongfen_muzang** — Excavated child jar coffin burial from a Neolithic Yangshao site in Henan, China: a large buff clay urn tilted in a shallow earthen pit with smaller clay vessels beside it, clean section-knife marks on the pit wall, small white survey labels and string grid, soft diffuse daylight, sober archaeological documentary photography, no human remains, no people, no readable text, no watermark
4. **yangshao_village/yangshao_bowuguan** — Small modern museum building in a Loess Plateau village, Mianchi, Henan, China: rammed-earth tone facade crossed by horizontal red and black painted-pottery band patterns, low terraces blending with loess hills behind, young trees and gravel forecourt, clear bright day, architectural photography, no signage text, no people, no watermark
5. **yanshi_shangcheng/gongcheng_yiji** — Palace precinct remains of the early Shang Yanshi city site, Henan, China: long rammed-earth foundation trenches and stone drainage culverts laid out between modern wheat fields, low protected earth mounds marking ancient walls, distant Yulaoshan hills, midday flat light, wide documentary archaeology photograph, no people, no text, no watermark
6. **yanshi_shangcheng/shiqi_shuidao** — Stone-slab drainage culvert of an early Shang palace at the Yanshi city site, exposed granite channel with plank grooves and cover stones in an excavation trench, protective shelter framing, soft daylight, documentary photography, no people, no text, no watermark
7. **zhengzhou_shangcheng/chengqiang_hangtu** — Towering rammed-earth Shang-dynasty city wall rising inside a modern Zhengzhou city park: exposed vertical section showing layered ramming courses and夯窝 tool marks, plane trees and lawn at its base, warm afternoon light, documentary photography, no people, no text, no watermark
8. **zhengzhou_shangcheng/shangdu_yuanbowuyuan** — Contemporary urban museum beside a green ruins park in Zhengzhou, China: angular earthen-toned facade stepping like an ancient rammed wall, bronze metal screen bands, evening blue hour, wide architectural photography, no signage text, no people, no watermark

```bash
# 转换模板（源 png 在 vibe_images/，目标文件名以 JSON 引用为准）
/c/tools-setup/ffmpeg/bin/ffmpeg.exe -y -loglevel error -i IN.png \
  -vf scale=1024:-2 -c:v libwebp -quality 78 OUT.webp
```

## 「示意图」角标机制

UI 计划 Task 4 `UiKit.MediaImage` 增加 `AI_SCHEMATIC_PATHS` 白名单常量（两批全部 AI 示意图路径：第一批 16 条 + 第二批遗址级 84 条，生成入仓后逐条加入），命中即右下角半透明「示意图」小标签；真实照片替换后从白名单移除。版权口径与 W6「数据来源与版权自查声明」同源维护。

## 真实照片·第一批（2026-10-03，Wikimedia Commons，`real_` 前缀，均已核许可）

| 路径 | 原文件 | 作者 | 许可 | 来源 |
|---|---|---|---|---|
| images/erlitou/real_yizhi_01.webp | 20240815 Erlitou Site 01.jpg | Windmemories | CC BY-SA 4.0 | https://commons.wikimedia.org/wiki/File:20240815_Erlitou_Site_01.jpg |
| images/erlitou/real_yizhi_02.webp | 20240815 Erlitou Site 04.jpg | Windmemories | CC BY-SA 4.0 | https://commons.wikimedia.org/wiki/File:20240815_Erlitou_Site_04.jpg |
| images/hanwei_luoyangcheng/real_yongning_tabji.webp | 20240815 Site of Luoyang City from Han to Wei Dynasty - Site of the Pagoda of Yongning Temple 01.jpg | Windmemories | CC BY-SA 4.0 | https://commons.wikimedia.org/wiki/File:20240815_Site_of_Luoyang_City_from_Han_to_Wei_Dynasty_-_Site_of_the_Pagoda_of_Yongning_Temple_01.jpg |
| images/hanwei_luoyangcheng/real_yizhi_bowuguan.webp | 20251018 Han-Wei Luoyang Ancient City Site Museum.jpg | Windmemories | CC BY-SA 4.0 | https://commons.wikimedia.org/wiki/File:20251018_Han-Wei_Luoyang_Ancient_City_Site_Museum.jpg |
| images/dongjing/real_zhouqiao_01.webp | 20251109 Site of Zhou Bridge 01.jpg | Windmemories | CC BY-SA 4.0 | https://commons.wikimedia.org/wiki/File:20251109_Site_of_Zhou_Bridge_01.jpg |
| images/dongjing/real_zhouqiao_02.webp | 20251109 Site of Zhou Bridge 03.jpg | Windmemories | CC BY-SA 4.0 | https://commons.wikimedia.org/wiki/File:20251109_Site_of_Zhou_Bridge_03.jpg |
| images/song_ling/real_yongzhaoling.webp | 20130405 Yongzhao Mausoleum.jpg | Windmemories | CC BY-SA 4.0 | https://commons.wikimedia.org/wiki/File:20130405_Yongzhao_Mausoleum.jpg |
| images/song_ling/real_songling_shengshan.webp | Northern Song Imperial Family Tomb - 3.jpg | Gary Todd | CC0 | https://commons.wikimedia.org/wiki/File:Northern_Song_Imperial_Family_Tomb_-_3.jpg |
| images/gongxian_yao/real_yaokui_yizhi.webp | 20240914 Gongyi Kiln Site.jpg | Windmemories | CC BY-SA 4.0 | https://commons.wikimedia.org/wiki/File:20240914_Gongyi_Kiln_Site.jpg |
| images/yangshao_village/real_yangshao_diceng.webp | Yangshao Culture Original Excavation Site- Yangshao & Longshan Strata.jpg | Gary Todd | CC0 | https://commons.wikimedia.org/wiki/File:Yangshao_Culture_Original_Excavation_Site-_Yangshao_%26_Longshan_Strata.jpg |
| images/yangshao_village/real_yangshaocun.webp | Yangshao Village.jpg | Gary Todd | CC0 | https://commons.wikimedia.org/wiki/File:Yangshao_Village.jpg |
| images/miaodigou/real_miaodigou_taogi.webp | Pots from the Yangshao Culture (3900-3600 BC), Miaodigou site, Sanmenxia, Henan.jpg | Furius | CC0 | https://commons.wikimedia.org/wiki/File:Pots_from_the_Yangshao_Culture_(3900-3600_BC),_Miaodigou_site,_Sanmenxia,_Henan.jpg |
| images/miaodigou/real_caitao_pen.webp | 20251026 Painted Pottery Bowl from Miaodigou.jpg | Windmemories | CC BY-SA 4.0 | https://commons.wikimedia.org/wiki/File:20251026_Painted_Pottery_Bowl_from_Miaodigou.jpg |
| images/duling_fangding/real_ruding_fangding.webp | 20260520 Nipple-Nailed Square Ding with Beast Face Patterns 01.jpg | Windmemories | CC BY-SA 4.0 | https://commons.wikimedia.org/wiki/File:20260520_Nipple-Nailed_Square_Ding_with_Beast_Face_Patterns_01.jpg |
| images/zhengzhou_shangcheng/real_shangcheng_qiang.webp | 20240817 Zhengzhou Shang City Site 01.jpg | Windmemories | CC BY-SA 4.0 | https://commons.wikimedia.org/wiki/File:20240817_Zhengzhou_Shang_City_Site_01.jpg |
| images/zhengzhou_shangcheng/real_chengqiang_02.webp | Shang Dynasty City Wall, Zhengzhou 01.jpg | Gary Todd | CC0 | https://commons.wikimedia.org/wiki/File:Shang_Dynasty_City_Wall,_Zhengzhou_01.jpg |
| images/wangchenggang/real_wangchenggang_yizhi.webp | Dengfeng Wangchenggang Yizhi 20181218 085045.jpg | Zhangzhugang | CC BY-SA 4.0 | https://commons.wikimedia.org/wiki/File:Dengfeng_Wangchenggang_Yizhi_20181218_085045.jpg |
| images/wangchenggang/real_wangwen_taoding.webp | 20241018 Grey Pottery Ding with Net Design, Wangchenggang Site 01.jpg | Windmemories | CC BY-SA 4.0 | https://commons.wikimedia.org/wiki/File:20241018_Grey_Pottery_Ding_with_Net_Design,_Wangchenggang_Site_01.jpg |
| images/xishuipo/real_bansu_longhu.webp | Human Burial and shell mosaics.National Museum, Beijing .JPG | Prof. Gary Lee Todd | CC BY-SA 4.0 | https://commons.wikimedia.org/wiki/File:Human_Burial_and_shell_mosaics.National_Museum,_Beijing_.JPG |

## 真实照片·第二批（2026-10-20，Wikimedia Commons，`China photographs taken on 2024-11-10` 分类）

> 这批是**本项目河南遗址的博物馆实拍**，不是遗址外景：拍摄者 Windmemories 于 2024-11-10 在郑州、洛阳、开封、濮阳一带
> 连续拍摄大河村遗址博物馆、西山遗址、青台遗址、二里头、大师姑等馆的展品与遗迹。
> 分类页：https://commons.wikimedia.org/wiki/Category:China_photographs_taken_on_2024-11-10
> 统一许可 CC BY-SA 4.0，作者 Windmemories（逐条见 `tools/commons_manifest.json`）。
> 下载与转码由 `tools/fetch_commons_images.py` 执行（长边 1280 / WebP q78）。

| 路径 | 原文件 | 落点 | 作者 | 许可 |
|---|---|---|---|---|
| images/dahecun/real_dahecun_bowuguan.webp | 20241110 Dahecun Site Museum.jpg | 大河村遗址博物馆 | Windmemories | CC BY-SA 4.0 |
| images/dahecun/real_dahecun_fangji.webp | 20241110 House Foundations of Dahecun Site 01.jpg | 大河村 F1 房址基址 | Windmemories | CC BY-SA 4.0 |
| images/dahecun/real_dahecun_caitao_pen.webp | 20241110 Painted Pottery Basin, Dahecun Site, Yangshao Culture.jpg | 大河村彩陶盆 | Windmemories | CC BY-SA 4.0 |
| images/dahecun/real_dahecun_caitao_bowl.webp | 20241110 Painted Pottery Bowl, Dahecun Site, Yangshao Culture 01.jpg | 大河村彩陶钵 | Windmemories | CC BY-SA 4.0 |
| images/dahecun/real_dahecun_xingwen_taopian.webp | 20241110 Red Pottery Bowl, Dahecun Site, Yangshao Culture.jpg | 大河村红陶钵（星纹彩陶片对照） | Windmemories | CC BY-SA 4.0 |
| images/dahecun/real_dahecun_moguang_heitao.webp | 20241110 Polished Black Pottery Cup, Dahecun Site, Yangshao Culture.jpg | 大河村磨光黑陶杯 | Windmemories | CC BY-SA 4.0 |
| images/dahecun/real_dahecun_shitao_ren.webp | 20241110 Stone Knives, Dahecun Site, Longshan Culture.jpg | 大河村龙山石刀 | Windmemories | CC BY-SA 4.0 |
| images/dahecun/real_dahecun_yu_shi.webp | 20241110 Jade Ornaments, Dahecun Site, Longshan Culture.jpg | 大河村龙山玉饰 | Windmemories | CC BY-SA 4.0 |
| images/dahecun/real_dahecun_gui.webp | 20241110 Pottery Gui, Dahecun Site, Yangshao Culture.jpg | 大河村陶鬲 | Windmemories | CC BY-SA 4.0 |
| images/dahecun/real_dahecun_guisheng.webp | 20241110 Pottery He, Dahecun Site, Yangshao Culture.jpg | 大河村陶盉 | Windmemories | CC BY-SA 4.0 |
| images/qingtai/real_qingtai_jar.webp | 20241110 Pottery Jar, Qingtai Site, Yangshao Culture.jpg | 青台遗址陶罐 | Windmemories | CC BY-SA 4.0 |
| images/qingtai/real_qingtai_ding.webp | 20241110 Pot Shaped Ding, Qingtai Site, Yangshao Culture.jpg | 青台遗址釜形鼎 | Windmemories | CC BY-SA 4.0 |
| images/qingtai/real_qingtai_caitao_bowl.webp | 20241110 Painted Pottery Bowl, Qingtai Site, Yangshao Culture.jpg | 青台遗址彩陶钵 | Windmemories | CC BY-SA 4.0 |
| images/kaifeng_xian/real_xishan_caitao_pen.webp | 20241110 Painted Pottery Bowl, Xishan Site, Yangshao Culture.jpg | 西山遗址彩陶盆 | Windmemories | CC BY-SA 4.0 |
| images/kaifeng_xian/real_xishan_xiaokou_ping.webp | 20241110 Pottery Bottle with Small Mouth and Pointed Bottom, Xishan Site, Yangshao Culture.jpg | 西山遗址小口尖底瓶 | Windmemories | CC BY-SA 4.0 |
| images/kaifeng_xian/real_xishan_tao_ding.webp | 20241110 Pottery Ding, Xishan Site, Yangshao Culture.jpg | 西山遗址陶鼎 | Windmemories | CC BY-SA 4.0 |
| images/kaifeng_xian/real_xishan_tao_jar.webp | 20241110 Pottery Jar, Xishan Site, Yangshao Culture 02.jpg | 西山遗址陶罐 | Windmemories | CC BY-SA 4.0 |
| images/erlitou/real_erlitou_dashigu_jar.webp | 20241110 Pottery Jar, Dashigu Site, Erlitou Culture.jpg | 大师姑二里头文化陶罐 | Windmemories | CC BY-SA 4.0 |
| images/erlitou/real_erlitou_li.webp | 20241110 Pottery Li, Dahecun Site, Erlitou Culture.jpg | 大河村出土、二里头文化陶器（馆签实为「刻槽盆」，原题 Pottery Li 与展签不一致，勿挂铜牌饰） | Windmemories | CC BY-SA 4.0 |
| images/erlitou/real_erlitou_zeng.webp | 20241110 Pottery Zeng, Dahecun Site, Erlitou Culture.jpg | 二里头文化陶甑 | Windmemories | CC BY-SA 4.0 |
| images/erlitou/real_erlitou_zun.webp | 20241110 Pottery Zun, Shang Dynasty.jpg | 商代陶尊 | Windmemories | CC BY-SA 4.0 |
| images/erlitou/real_erlitou_yaogu_zun.webp | 20241110 Proto-Porcelain Zun, Shang Dynasty.jpg | 商代原始瓷尊 | Windmemories | CC BY-SA 4.0 |

### 仍在库可用、待挂载的同分类图（2024-11-10）

以下文件同样在 Commons 上可取，属于本项目已收录遗址／器物，尚未写入 JSON
（`tools/commons_manifest.json` 里已登记，限流窗口过后跑 `python tools/fetch_commons_images.py` 即可补齐）：

| Commons 文件名 | 归属 | 拟挂落点 | 状态 |
|---|---|---|---|
| 20241110 Painted Pottery Urn, Dahecun Site, Yangshao Culture.jpg | 大河村彩陶瓮 | 大河村遗址图集（本址器物；不放他址文物卡） | 清单已登记 |
| 20241110 Antlers, Dahecun Site, Longshan Culture.jpg | 大河村鹿角 | dahecun | 清单已登记 |
| 20241110 Bone Dagger, Dahecun Site, Yangshao Culture.jpg | 大河村骨匕首 | 大河村遗址图集 | ✅ 已落盘 |
| 20241110 Turtoise Shell, Dahecun Site, Longshan Culture.jpg | 大河村龟甲 | 大河村遗址图集 | ✅ 已落盘 |
| 20241110 Pottery Spindle Wheels, Dahecun Site, Longshan Culture.jpg | 大河村陶纺轮 | 大河村遗址图集 | 清单已登记 |
| 20241110 Stone Spindle Wheels, Dahecun Site, Longshan Culture.jpg | 大河村石纺轮 | 大河村遗址图集 | 清单已登记 |
| 20241110 Stone Spear, Mazhuang Site, Longshan Culture.jpg | 马庄石矛 | 暂不挂载（本址文物为灰坑、石锛石镰，器类不符） | 清单已登记 |
| 20241110 Pottery Jar, Mazhuang Site, Longshan Culture.jpg | 马庄陶罐 | 暂不挂载（同上） | ✅ 已落盘 |
| 20241110 Pottery Basin with Two Handles, Mazhuang Site, Longshan Culture.jpg | 马庄双耳盆 | 暂不挂载（同上） | ✅ 已落盘 |
| 20241110 Diorama of Dahecun.jpg | 大河村沙盘 | 大河村遗址图集 | ✅ 已落盘 |
| 20241110 Polished Black Pottery Cup, Dahecun Site, Yangshao Culture.jpg | 大河村磨光黑陶杯 | `dhc_moguang_heitao`（取到后挂文物卡） | 限流未取 |
| 20241110 Pot Shaped Ding, Qingtai Site, Yangshao Culture.jpg | 青台釜形鼎 | `qt_qingtai_lei_xi`（取到后与陶罐、彩陶钵并列为组合） | 限流未取 |
| 20241110 Pottery Bottle with Small Mouth and Pointed Bottom, Xishan Site, Yangshao Culture.jpg | 西山小口尖底瓶 | 暂不挂载（本址文物为彩陶片、黑陶豆柄） | 限流未取 |
| 20241110 Pottery Jar, Dashigu Site, Erlitou Culture.jpg | 大师姑陶罐 | 暂不挂载（大师姑不在 42 处名录内） | 限流未取 |
| 20241110 Pottery Zun, Shang Dynasty.jpg | 商代陶尊 | 暂不挂载（与二里头青铜礼器不同器类） | 限流未取 |
| 20241110 House Foundations of Dahecun Site 02–05.jpg | 大河村房址 | dahecun | 清单已登记 |
| 20241110 Sign of National Cultural Heritage Protection at Dahecun Site.jpg | 大河村国保碑 | dahecun | 清单已登记 |

> 另有一批 2024-11-10 之外的 Zhengzhou 公交／地铁／学校照片，与本项目无关，**不取**。

### 当前实拍覆盖（2026-11-04 第三轮后）

| 口径 | 覆盖 | 说明 |
|---|---|---|
| 遗址级（42） | **42 / 42** | 每处遗址均有实拍头图。优先取"遗址/建筑实景"，其次"代表性器物"；仍无专属实拍的聚合档案遗址，用**同类遗存**补位（例：万王城台址→荥阳故城城址、新砦龙纹陶片→大河村彩陶片） |
| 文物级（104） | **104 / 104** | 全部文物均有实拍。跨遗址借用只在**器型完全一致**时进行（黑陶杯↔黑陶杯、铜爵↔铜爵）；其余按材质与形制就近匹配 |
| 遗址图集 | 67 处 | 同一遗址的第 2、3 张图挂在 `site.images` 里，详情页灯箱直接可放大，不再是"躺在 rawfile 里没人引用"的白背 |
| 磁盘实拍文件 | 101 张 | 全部经 `PIL.verify()` 解码校验；署名记录 `rawfile/attribution.json` 101 条一一对应，许可分布 CC BY-SA 4.0×83 / CC0×17 / CC BY-SA 3.0×1 |
| 引用完整性 | 172 条 real_ 引用 | 脚本核对：全部命中磁盘文件，**零断链、零未引用** |
| HAP 体积 | 24.4 MB | 限 40 MB，尚有富余 |

> **门禁守住了这件事**：`validate_sites` 会把"在盘上但内容没引用"的 `real_` 图判红
> （白进 HAP），`attribution` 门禁会核对每张在包实拍是否都有署名记录。
> 本轮两次被它们拦下并修掉——这正是门禁存在的意义。

> 剩余风险已如实记录：跨遗址借用的图在**文物名与照片**上不是同一件器物，
> 属"同类标本"而非"该文物本体"。页面上作为展陈实景使用，不在文案中宣称
> 是该文物的出土影像；后续若补到该器物专属实拍，优先替换。

### 2026-10-25 归属校正（照片与展签逐条对题）

原则：**遗址头图只放遗址外景/现场遗迹，文物卡只放同器类、同出处的器物**；
"同址同类对照图"不再挂到别的文物上（此前出现过铜牌饰配刻槽盆、石象生当遗址头图等错配）。

| 原挂法 | 问题 | 现挂法 |
|---|---|---|
| 二里头·铜牌饰 ← real_erlitou_li | 图为陶质刻槽盆（Commons 原题也注明出土于大河村），与铜牌饰无关 | 撤下，回到剪影；该图并入大河村遗址图集 |
| 二里头·陶甑图存 erlitou 目录 | 实际出土于大河村（二里头文化） | 并入大河村遗址图集 |
| 开封先民·彩陶片 ← 西山彩陶盆 | 整器盆不是"残片" | 撤下；该图暂不挂载 |
| 开封先民·黑陶豆柄 ← 西山陶鼎 | 鼎不是豆柄 | 撤下；该图暂不挂载 |
| 大河村·星纹彩陶片 ← 红陶钵 | 原题即"红陶钵（星纹残片对照）" | 撤下并入遗址图集 |
| 北宋皇陵·头图 ← 石象生 | 石象生是陵前石刻，不是陵区外景 | 石象生改挂文物 `sl_wangzhu_xiang`；头图改永昭陵 |
| 王城岗·头图 ← 灰陶鼎 | 器物当遗址封面 | 灰陶鼎改挂 `wcg_longshan_black_pottery`；头图改遗址碑 |
| 西水坡·头图 ← 蚌塑龙虎 | 考古发现（M45）当遗址封面 | 改挂 `xsp_beng_long` / `xsp_beng_hu`；遗址头图回退年代色 |
| 青台·头图 ← 陶罐 | 器物当遗址封面 | 陶罐 + 彩陶钵改挂 `qt_qingtai_lei_xi`（陶器组合恰为多件） |
| 尉氏邱集·头图 ← 陶罐 | 器物当遗址封面，且本址文物是灰坑/石锛石镰 | 撤下，头图回退年代色 |
| 庙底沟·头图 ← 彩陶盆/陶器组 | 器物当遗址封面，且残片≠整器 | 撤下，头图回退年代色 |
| 汉魏洛阳城·头图 ← 博物馆 | 博物馆内景不如塔基现场 | 永宁寺塔基置首，博物馆排图集 |

仍可用但未挂载的 8 张（等有对得上的展签再用）：西山彩陶盆 / 西山陶鼎 / 西山陶罐 / 庙底沟彩陶盆 / 庙底沟陶器组 / 马庄双耳盆 / 马庄陶罐 / 商代原始瓷尊。

王城岗的「城墙夯土遗存」「青铜容器残片」在 Commons 只有遗址碑与陶器照片，没有对应实物图，继续用藏品签占位（编号 L2 · 002 / 003），不以他址图片顶替。

### 2026-10-25 补图轮（15 张新挂载）

检索通路变了：本机直连 `commons.wikimedia.org` 的 API 已超时（该域名解析到 103.102.166.224），
但 `upload.wikimedia.org`（103.102.166.240）可直连。所以**检索走云端代理**
（`tools/.sync_probe/` 下的候选清单由四路并行检索产出），**下载在本地**
（`tools/fetch_commons_images.py`，分段 Range + 魔数校验 + webp 1024/q78），
挂载走 `tools/mount_real_images.py`，许可台账并入 `tools/commons_manifest.json`。

| 挂给谁 | Commons 文件 | 许可 / 作者 |
|---|---|---|
| 开封铁塔 头图 | 20250622 Iron Pagoda Park 01.jpg | CC BY-SA 4.0 / Windmemories |
| 铁塔·琉璃雕砖构件 | 开封铁塔琉璃瓦.jpg | CC BY-SA 3.0 / Gisling |
| 东周王城 头图 | 20241215 Chariot Pit of Luoyang Wangcheng 04.jpg | CC BY-SA 4.0 / Windmemories |
| 王城·天子驾六车马坑 | 20241215 Chariot Pit of Luoyang Wangcheng 01.jpg | 同上 |
| 偃师商城 头图 | 偃师商城遗址-池苑基址.jpg | CC BY-SA 4.0 / Ma3r |
| 渑池仰韶村 头图 | Yangshao Culture Original Site.jpg | CC0 / Gary Todd |
| 虢国墓地 头图 | Guo State Tomb 1.jpg | CC0 / Gary Todd |
| 虢国·玉柄铁剑 | Western Zhou Iron Sword with Jade Handle.jpg | CC0 / Gary Todd |
| 虢国·虢季鼎 | 虢季墓列鼎（之一） 20160924.jpg | CC BY-SA 4.0 / Siyuwj |
| 二里头·乳钉纹铜爵 | 20250529 Bronze jue with nipples in the Erlitou Site Museum of the Xia Capital.jpg | CC BY-SA 4.0 / Yumeto |
| 二里头·绿松石兽面铜牌饰 | Turquoise plaques, beast-mask design, Erlitou site, Yanshi, Henan.jpg | CC0 / Furius |
| 二里头·绿松石龙形器 | 绿松石龙形器及铜铃, 2024-06-23.jpg | CC BY-SA 4.0 / Siyuwj |
| 州桥·桥壁石刻壁画 | 20250531 Carving next to the Zhou Qiao.jpg | CC BY-SA 4.0 / Yumeto |
| 州桥·汴河河道与堤岸 | 20250531 Canal section near the Zhou Qiao.jpg | CC BY-SA 4.0 / Yumeto |

**下了但没挂的 3 张**（留在 `tools/.sync_probe/rejected/`，不进包）：
潼关故城 ← `202309 Tongguan Ancient City Overview.jpg` 是从南原北望的黄河—渭河交汇全景，
画面里的城楼是复建景区，不能当「汉潼关故城」头图；荥阳故城 ←
`20240906 Site of the Fortresses of Liu Bang and Xiang Yu 01.jpg` 的国保碑写的是
**汉霸二王城**（荥阳广武），与「荥阳故城」（惠济区古荥镇）是两处文保单位；
永昭陵陵台 ← `20250614 Yongzhao Mausoleum 07.jpg` 拍的是神道石像生，
与卡片点名的「陵台与上宫」不是同一对象（且与遗址头图重复）。

**检索到但按规则舍弃的主要项**：杜岭方鼎（Commons 全部照片属河南博物院藏**二号**，
一号在国博无图）；大河村磨光黑陶杯（馆签为**仰韶**，卡片写龙山期）；
庙底沟花瓣纹彩陶**残片**、大河村星纹**彩陶片**（只有整器图，整器≠残片）；
宋东京宫城「州桥双龙壁」（与北宋东京城遗址同图，且州桥不属宫城）；
永宁寺舍利容器、太极殿、西朱村器物、荥阳铁炉、郐国、邱集、苏羊、王湾、新砦、
启封、汴州、帝丘等——Commons 只有街景、同形异地（"太极殿"全是北京故宫、
"邵公垒"命中山东临朐、"金堤"命中韩国金堤）或同址不同器类。

### 2026-10-25 第二轮（改走分类遍历，+18 处挂载）

第一轮按关键词搜，标题里没有遗址名的文件全漏了；第二轮改用
`generator=categorymembers` 遍历分类，靠 `ImageDescription` 与分类名认出处，
一次调用可拿 100 个文件。新挂 18 张（许可与分类逐条经批量 `titles=` 复核）：

| 挂给谁 | Commons 文件 | 许可 / 作者 | 认出的依据（分类或碑文） |
|---|---|---|---|
| 潼关故城 头图 | 202309 Ruins of Tongguan City (Han).jpg | CC BY-SA 4.0 / MNXANL | 碑文「潼关汉城遗址·陕西省文物保护单位」 |
| 宋东京宫城 头图 | 20250531 Site of the Daqing Hall.jpg | CC BY-SA 4.0 / Yumeto | Site of Dongjing City of Northern Song Dynasty |
| 宫城·东京城垣与路土叠压层 | 20250531 Site of the north wall of the imperial city.jpg | CC BY-SA 4.0 / Yumeto | 同上（内城北墙基址） |
| 宫城 图集 | 20250622 Site of the West Wall of the Imperial Palace.jpg | CC BY-SA 4.0 / Windmemories | 同上 |
| 启封故城 头图 + 图集 | 20250615 Site of Ancient Qifeng 01 / 02.jpg | CC BY-SA 4.0 / Windmemories | Site of Ancient Qifeng + 国保碑「启封古城」 |
| 小双桥 头图 | 20251207 Xiaoshuangqiao Site 02.jpg | CC BY-SA 4.0 / Windmemories | Xiaoshuangqiao Site |
| 小双桥·青铜建筑构件 | 20260408 Bronze Architecture Ornament with Animal-Mask Motif.jpg | CC BY-SA 4.0 / Windmemories | Xiaoshuangqiao Site + Henan Museum 藏 |
| 小双桥 图集 | 20241018 Grey Pottery Jue, Xiaoshuangqiao Site.jpg | CC BY-SA 4.0 / Windmemories | 同址灰陶爵（卡片是「白陶器类」，只进图集不当本器） |
| 荥阳故城 头图 + 图集 | 20240929 Site of Ancient Xingyang 01 / 03.jpg | CC0 / Windmemories | Site of Ancient Xingyang（与「汉霸二王城」区分开） |
| 荥阳故城·汉代冶铁炉基与积铁 | 20260322 Site of the No. 1 Furnace of Guxing Iron Smelting Site.jpg | CC BY-SA 4.0 / Windmemories | Guxing Iron Smelting Site |
| 西朱村曹魏墓 头图 | 西朱村曹魏墓 M1 考古现场.jpg | CC BY-SA 4.0 / Ma3r | Cao Wei Tombs in Xizhu Village |
| 汉魏洛阳城太极殿 头图 | 20240815 …Site of the Palace City 01.jpg | CC BY-SA 4.0 / Windmemories | 宫城中轴与太极殿基址航拍 |
| 太极殿·太学壁经残石 | 熹平石经·周易残石…西安碑林第三室.jpg | CC BY-SA 4.0 / Kcx36 | Xiping Stone Classics |
| 虢国墓地·组佩玉器 | 20260520 Jade Pendant Formed by Seven Huang and Gold Belt Ornaments.jpg | CC BY-SA 4.0 / Windmemories | Tomb of Guo Ji (M2001) + 河南博物院藏玉 |
| 汉魏洛阳城·永宁寺塔基泥塑像 | Clay Head of Bhikkhu Excavated at Yongning Temple.jpg | CC BY-SA 4.0 / Baomi | Yongning Temple of Luoyang（龙门博物馆藏） |
| 偃师商城·石砌排水暗渠 | 偃师商城遗址-池苑基址-排水道.jpg | CC BY-SA 4.0 / Ma3r | Yanshi Shang City Site |
| 郑州商城·牛首尊 | 20241018 Bronze Zun of Bull Head and Beast-Face Designs 01.jpg | CC BY-SA 4.0 / Windmemories | Artifacts from Zhengzhou Shang City Site |
| 郑州商城·刻字卜骨 | 20241018 Oracle Bones.jpg | CC BY-SA 4.0 / Windmemories | Collections of the Zhengzhou Museum |
| 渑池仰韶村·采集陶片组 / 灰坑遗迹 | …Original Excavation Site- Potsherd 1 / Ash Layer.jpg | CC0 / Gary Todd | Yangshao Culture Museum and Original Site |

第二轮仍按口径拒掉的：仰韶村小口尖底瓶与彩陶盆（`Yangshao Culture Pottery 01–42` 出处明确
但元数据不写器形，只给 low）、杜岭方鼎一号（国博藏，Commons 无实拍）、庙底沟花瓣纹残片与
大河村星纹残片（只有整器图）、宋东京宫城「州桥双龙壁 / 汴河壁岸」（与北宋东京城遗址两张卡
重复用图）、邵公垒（检索误报东周王城车马坑图）、偃师与汴州故城（low，指认不到本体）。
濮阳、河堤口、开封史前群、戚城、郐国、苏羊、王湾、新砦、邱集、帝丘在 Commons **无任何分类**，
属彻底无源，长期保持年代色与藏品签。

### 2026-10-25 第三轮（未展开分类继续挖，+5 处挂载）

前两轮把"能想到的关键词"搜完了，第三轮专攻**从没展开过的大分类**
（`Zhou Bridge`、`Luoyang City of the Eastern Han to Northern Wei Dynasty`、`Hangu Pass (Han Dynasty)`、
`Cao Wei Tombs in Xizhu Village`、`Miaodigou Site`、`Sancai ceramics of the Tang Dynasty in the Luoyang Museum`、
`Yongzhao Mausoleum`、郑州博物馆陶瓷/青铜子分类），新落盘 9 张、挂载 5 处：

| 挂给谁 | Commons 文件 | 许可 / 作者 | 认出的依据 |
|---|---|---|---|
| 汉魏洛阳城·铜驼街御道 | 20240815 …Site of the Tongtuo Street.jpg | CC BY-SA 4.0 / Windmemories | Luoyang City of the Eastern Han to Northern Wei Dynasty |
| 庙底沟·花瓣纹彩陶 | 20260408 Petal-Patterned Painted Pottery Bowl.jpg | CC BY-SA 4.0 / Windmemories | Miaodigou Site + Yangshao Culture potteries in the Henan Museum |
| 郑州商城·原始瓷器 | 20241018 Proto-Celadon Zun.jpg | CC BY-SA 4.0 / Windmemories | Proto-porcelain of Shang Dynasty + Artifacts from Zhengzhou Shang City Site |
| 大河村·磨光黑陶杯 | Longshan Pottery Cup (10324955424).jpg | CC0 / Gary Todd | Longshan Culture potteries in the Zhengzhou Museum（器类对、馆对） |
| 仰韶村·小口尖底瓶 | 20241018 Red Pottery Bottle with Small Mouth and Pointed Bottom.jpg | CC BY-SA 4.0 / Windmemories | 馆签原文「红陶小口尖底瓶」（青台出土，卡片写仰韶期，同类不同址——按"器类优先"挂载并在此注明） |

**下了但核图后撤下的 3 张**（图与卡片点名的不是同一对象，留盘不挂）：
- `20250531 Carving next to the Zhou Qiao.jpg` ← 州桥·双龙壁：实为**发掘坑全景**（河道剖面与石壁），不是桥壁双龙雕刻；
- `20260503 Site of Hangu Pass in Xin'an 04.jpg` ← 潼关·古城垣夯土与条石基址：实为**复建关楼与石像生门道**，夯土基址未入画；
- `20251026 Pottery Cauldron and Stove from Miaodigou.jpg` ← 庙底沟·直口深腹陶缸：实为**陶灶+陶釜**组合，缸不成立。

**遇到的新坑（已写入 PITFALLS #62）**：`upload.wikimedia.org` 连拉 14 张大图触发 robot policy 的
**HTTP 429**，退避 30s×n 仍持续；同机再开一路探测会把限流坐实。实测一次 429 后约 5 分钟才恢复。



### 2026-10-25 第三轮续（缩略图通路 + 严格核图，再 +2 处挂载）

429 失败的 8 项改走 Commons **固定档缩略图**后 10/10 全过（数分钟跑完；原图通路一张要 10 分钟以上）。
Commons 只渲染固定宽度缩略图（20/40/60/120/250/330/500/960/1280/1920/3840px），
**非标准宽直接 400**。本项目成品要求就是长边 1024，故取 1280px 档再本地压回 1024（见 PITFALLS #62）。

核图后只再挂 2 处，其余全部撤下（宁缺勿错）：

| 挂给谁 | Commons 文件 | 许可 / 作者 | 认出的依据 |
|---|---|---|---|
| 宋陵·永昭陵陵台与上宫 | 20230216 Yongzhao Mausoleum 01.jpg | CC BY-SA 4.0 / Windmemories | Yongzhao Mausoleum（上宫红墙 + 陵台封土航拍） |
| 巩义窑址·唐三彩釉陶残片与马俑 | Tang Sancai Glazed Porcelain Horse (10233867724).jpg | CC0 / Gary Todd | Sancai ceramics of the Tang Dynasty in the Luoyang Museum |

**核图撤下 8 张**（图与卡片点名的对象不符，留盘不挂、台账留底）：
- `20250531 Canal section near the Zhou Qiao.jpg`：第二轮已挂给「汴河河道与堤岸」卡，同图不进两址；
- `20250531 Zhou Qiao.jpg`（州桥全景）：画面属北宋东京层，挂汴州故城「大梁—浚仪城址层」= 同址不同期；
- `20240815 …Site of Pi Yong.jpg` / `…Site of the Palace City 04.jpg`：实拍是**国保碑**，不是辟雍/太极殿基址本体；
- `20240815 Mount Mang from…jpg`：主体是拖拉机与风电场，邙山只在远景；
- `20260503 Site of Hangu Pass in Xin'an 04/07.jpg`：**新安汉函谷关**（洛阳新安）≠ 卡片的潼关古城垣，同名异地；
- `西朱村曹魏墓 M1 考古现场.jpg`：已是本址头图，不重复当「刻铭石牌」卡图（石牌实物 Commons 无图）；
- `20251026 Painted Pottery Basin from Miaodigou.jpg`：整器盆，「直口深腹陶缸」卡不放；
- `20230216 Yongzhao Mausoleum 02.jpg`：与陵台卡同址重复，且内容是上宫建筑群不是神道。

另对第一轮挂载做一次复账：`Longshan Pottery Cup (10324955424).jpg`（CC0）的分类只有
"Longshan Culture potteries in the Zhengzhou Museum"，非大河村出土——挂给「磨光黑陶杯」卡
走的是"器类优先"口径（器类对、藏馆对），在此注明供评审复核；若评审要求"必须同址"，撤下即回藏品签。

模拟器实机抽查（2026-10-26 凌晨）：宋陵详情页头图（神道石象生）与「永昭陵陵台与上宫遗址」卡
（L6·002，上宫航拍）出图正常，与「陵前石象生组群」（L6·001）不重图；巩义窑址
「唐三彩釉陶残片与马俑」卡（L5·001）出图，同址其余两卡仍为线稿藏品签。

### 2026-10-26 第四轮（打包瘦身 + 引用修复，非补图）

第五轮检索做完、下载却被 Wikimedia 出口卡住，这一轮先把**已在仓的账目问题**结掉。

**① rawfile 里有 3.40 MB 根本不用的图。** 前三轮"核图撤下"的 21 张 `real_`
只做了"不挂载"，文件仍躺在 `rawfile/images/` 里被一起打进 HAP
（19 张是本会话下载后未挂的未跟踪件，另 2 张 `real_caitao_pen` /
`real_miaodigou_taogi` 早先已被提交跟踪过——`.gitignore` 挡得住 git，
挡不住 hvigor 打包）。逐张比对"JSON 引用集 vs 盘上文件集"确认这 21 张零引用后，
移到 `tools/staging_unmounted/`（不删——它们是核过许可的候选，
留给能读图的会话复核；`tools/fetch_commons_images.py` 的 `--out`
默认值也因此从 rawfile 改成了这个暂存区）。

**② 派生目录被当资源打了包。** `validate_sites.py` 缺省把发布版写到
`<src>/../sites-out`，对 `rawfile/sites` 就是写进 rawfile——42 份与
`sites/*.json` 同源的重复 JSON 进了 HAP（且 `.gitignore` 只挡 git，不挡打包）。
输出根改为固定 `tools/sites-out`，历史产物一并移出。顺带 `rawfile/_audit.txt`
（7.4 KB 早期审计转储，无引用）也移出资源树。

**③ 9 条图片引用少写了 `images/<遗址>/` 前缀**，其中 3 条正好是文物卡主图
（大河村「星纹彩陶片」、开封先民「仰韶期彩陶片」「龙山期磨光黑陶豆柄」），
其余 6 条落在灯箱翻页上——文件其实在盘上，`$rawfile` 取不到就静默回落剪影，
界面上看不出错。
根因是 `check_site()` 只查 enum/minItems/maxItems，**从不应用 schema 的
`items.pattern`**，而文物级 `images` 连 pattern 都没写。
两处一起补：新增 `check_paths()` 对遗址级与文物级统一校验
`^images/[a-z0-9_]+/[a-z0-9_]+\.webp$` 并查文件存在性
（存在性仅在源树位于 `rawfile/` 下时启用，`tools/sites-src` 母本不强制）；
9 条路径按 token 精确补齐，不动其余排版。

复验：`validate_sites.py` 对 `rawfile/sites` 与 `tools/sites-src` 均 exit 0
（加固前先如实报出这 9 条并 exit 1）；7 项门禁逐个 exit 0；
`node --test` 65/65；重建 HAP 20.14 MB，装机后逐条从**包内**核对
——261 条图片引用 0 缺失，8 个修复路径的 JSON 引用与 webp 实体均在包内。

**④ 把这条链路的方向性补上，避免复发。** `fetch_commons_images.py` 的
`--out` 默认落点从 `rawfile/images` 改成 `tools/staging_unmounted`，
`mount_real_images.py` 挂谁就把谁从暂存区复制进 rawfile——**rawfile 里
从此只出现"已被决定要挂"的图**；`validate_sites.py` 另加反向差集硬闸
（未挂载的 `real_` 图直接 FAIL）。两个改动都用受控用例验过：
暂存区命中→提升进包、两处都无→PROBLEM 且不动 JSON、
clean 树 exit 0、塞一张未挂 `real_` 立刻 exit 1、塞一张非 `real_` 不判红。
反向差集要先扫 `EraTheme.ets`（那里按年代硬编码了 6 张年代兜底图，
只查内容 JSON 会把在用的图误报成死重）；自有示意图仍按"报数不判红"处理，
因为 IMAGES.md 给它们记着待生成配额——当前 6 张 0.10 MB：
`erlitou/xiadu_bowuguan`、`miaodigou/bowuguan_waiguan`、`qingtai/huanhao_jubu`、
`song_ling/yongzhao_gongyuan`、`xishuipo/ertongfen_muzang`、
`yangshao_village/yangshao_bowuguan`，属内容线待办，不在本轮判红。

**⑤ 第五轮检索的结论（图未下，账先记下）。**
- `Category:Miaodigou Site` 全部 15 个文件都是博物馆器物照，**没有一张庙底沟遗址本体**，头图仍无解；
  器物侧 盆/碗/釜灶 与「直口深腹陶缸」不是同一器类，维持前几轮的否决。
- **`File:Suoyang City 04.jpg`（Zanhe, CC BY-SA 4.0）看着是"苏羊遗址外郭城南墙"，实为
  甘肃酒泉〈锁阳城〉**——`Category:Suoyang City` 全类 16 个文件都在讲锁阳城与塔儿寺。
  又一例同名异地，苏羊遗址头图继续空着。
- 西水坡、青台、班村、王湾按 `"silkworm" OR "Qingtai" OR "Suoyang" OR "Xishuipo"` 检索，
  命中全是家蚕生物图与德国教堂，无可用考古图。

### 2026-10-26 第五轮（示意图死引用清退，非补图）

回答"每个地方都有图片吗"时盘出一个比缺图更严重的事实：**内容 JSON 里写的示意图，
一张都不会上屏。**

渲染侧每一处都先过实拍筛选——头图 `firstRealImage(site.images)`（DetailPage:704、
ListPage:450）、图集 `realImagesExclude(...)`（DetailPage:943/946）、文物卡
`firstRealImage(r.images)`（DetailPage:569、RelicPage:355）、灯箱
`r.images.filter(isRealImage)` 与 `siteRealImages()`（DetailPage:348/578）。
非 `real_` 的路径写在数组里等于没写，但文件仍被 hvigor 打进包。
唯一真正渲染的示意图是 `EraTheme.ERA_COVER_IMAGES` 那 6 张首页年代卡封面，
它们是**硬编码在 .ets 里**、不经内容 JSON 的。

据此执行"维持实拍门槛"这条路：

| 动作 | 数量 | 去处 |
|---|---|---|
| 从 42 个站点 JSON 摘除死引用 | 184 条（遗址位 80 + 文物位 104） | 直接删除该数组项 |
| 移出不再被引用的示意图文件 | 110 个 2.05 MB | `design/illustrations/<遗址>/`（已脱离资源树、不再打包；110 个文件当前未跟踪，要再提交一次才算入库） |
| 保留在包内的示意图 | 6 张 | EraTheme 首页封面，按源码解析出的清单保护 |
| 摘除后剩余引用 | 77 条，全部 `real_` | 一图两卡 1 例（西水坡蚌塑龙虎同图） |

配套口径：`tools/site.schema.json` 两级 `images` 的 pattern 收紧为只允许
`real_`，文物级 `minItems: 1` 放开（无实拍卡走藏品签+材质剪影是设计稿的正式态，
不是缺数据）；`validate_sites.py` 的 `check_paths()` 对**进包树**按 `real_` 硬卡，
对 `tools/sites-src` 母本只校路径形制——母本的职责是留全量语料（含示意图），
且它是手写紧凑数组排版，硬卡会逼出一整轮无意义重排（实测往返不逐字节一致，
已就地止步，母本零改动）。

顺带纠一处旧账：本文档此前记"遗址图集 6 处"，实际是 **10 址**图集非空
（大河村 13 张，另 9 址各 2 张）。

实机复验（模拟器，2026-10-26 上午）：首页→仰韶层列表→班村遗址详情页，
`site.images` 摘成空数组后页面正常加载、头图位显示「图像整备中」占位块，进程存活；
列表页同类无实拍条目也走同一占位态。文物卡区在 dumpLayout 的可见节点集里没取到
（下滑未生效），因此**该态未做屏上复核**——但它是本变动的既有效果：那 71 张卡
此前挂的是示意图，`firstRealImage` 本来就返回空串，改成空数组后行为逐字节相同，
渲染分支从未因这次改动而改变。

### 覆盖（第五轮后）

| 口径 | 覆盖 | 说明 |
|---|---|---|
| 遗址级头图（42） | **22** | 无实拍 20 处回退层色整块；本轮不再拿示意图冒充 |
| 文物级卡图（104） | **33** | 其余 71 卡走藏品签 + 材质剪影（104 卡材质全部可归类，仅 `tg_guanshu_wenwu` 记 `mixed` 落通用 `jue.svg`） |
| 遗址图集 | **10** 址 | 大河村 13 张 + 9 址各 2 张；旧记"6 处"已纠 |
| 首页年代卡 | 6/6 | EraTheme 硬编码 AI 示意图 + 角标，唯一允许非实拍上屏的图位 |
| 进包图片文件 | 82 张 13.29 MB | 76 实拍 + 6 首页封面；包内 77 条引用全部有效且全部 `real_` |
| 自有示意图 | 110 张 2.05 MB | 移入 `design/illustrations/`，不再打包（提交后才入库） |
| 核图未挂暂存 | 21 张 3.40 MB | `tools/staging_unmounted/`，等可判图的会话定去留 |
| HAP 体积 | **18.19 MB** | 24.0 → 20.14 → 18.06 →（第六轮 +attribution.json 35 KB、OFL 原文 8.7 KB 与版权页代码）18.19（限 40 MB） |

### 2026-10-26 第六轮（署名合规落地，非补图）

第五轮把"每张图到底上不上屏"查清了，这轮查的是另一件一直没做的事：**这批图的版权**。
Wikimedia Commons 不是"免费图"的同义词——在包 76 张实拍的许可分布是

| 许可 | 张数 | 义务 |
|---|---|---|
| CC BY-SA 4.0 | 60 | 署名 + 许可链接 + 说明修改 + 同许可证分享演绎 |
| CC BY-SA 3.0 | 1 | 同上（3.0 条文编号不同，改动说明同样要求） |
| CC0 | 15 | 无强制义务，仍逐条记录出处 |

可核验的事实只到这一层：**在包 76 张里没有 `Public domain`、没有 `CC BY-NC`／`CC BY-ND` 系**
（许可串逐条来自 Commons 元数据，见 `rawfile/attribution.json`）。至于检索过程中是否曾遇到
NC/ND 候选并据此排除，前几轮的台账没有留这条记录，故不在此声称——`check_attribution.py`
也只按"记录必须与元数据一致"卡，不假设历史上筛过什么。

违约事实是核验过的：本轮改动前 `git grep -i "CC BY|creativecommons|署名" HEAD -- app/`
在整个应用树里**只命中一处**，还是 `kaita.json` 正文里讲铁塔砖文"分工与署名习惯"的内容词，
与许可无关——也就是说 61 张 BY-SA 的图此前在屏上与包内都没有任何署名（不影响渲染，所以看不出来）。

**数据链路**（`docs/IMAGES.md` 各批次表 + `tools/commons_manifest.json` → `rawfile/attribution.json`）：

```
python tools/build_attribution.py     # 幂等重建；缺口逐条报出并 exit 1
python tools/check_attribution.py     # 门禁：在包 real_ ↔ 记录 双向差集 + 字段硬卡
```

三条踩过的坑，写在这里防下一轮重犯：

1. **manifest 不是全集**。它只覆盖 58/76 张——后两轮走分类遍历挂的图没回写台账，
   补齐要靠 `docs/IMAGES.md` 的批次表。所以生成器同时读两处，并要求"任何一张在包图
   两处都查不到"就判失败，而不是静默出一张不完整的版权页。
2. **表头列序各批次不同**（第二批是 `路径|原文件|落点|作者|许可`，第一批另有顺序）。
   按位置取列会错配 13 行——作者列读到"落点"。必须按列名映射。
3. **Commons 链接要归一化**。`file` 字段有的带 `File:` 前缀、有的中文/空格未编码，
   直接拼会产出 `File:File:` 或 404 链接（本批 21 张是中文名）。`build_attribution.py`
   里剥前缀 + `quote(safe='')`；`licenceUrl()` 只认得出的许可，认不出返回空串，
   **不猜 URL**。

**屏上落点**（署名要出现在作品旁边，不能只塞进一个没人点的页面）：

- `pages/CreditsPage.ets`（「我的」第 05 行「图片版权与来源」）：按许可分组、需署名组排前，
  组内按原文件名稳定排序；逐张显示原文件名 / 作者 · 许可 / Commons 来源链接，许可链接与
  来源 URL 均可长按复制；顶部三张说明卡是「记录口径」「对原图的改动」「示意图说明」。
- `common/ImageViewer.ets` 灯箱底部逐张图注 `作者 · 许可`（新增 `credits` 入参，由
  `DetailPage.openViewer` 用 `creditsFor()` 按 path 查表填充；示意图与未入仓不给空行）。
- 改动口径全批一致，只在页面上讲一次：`已按本项目用途调整：长边缩放至 1024、重编码为 WebP（原图为 JPEG）`。
- 6 张首页年代卡封面的 AI 示意图另有一张披露卡，并写进 `attribution.json` 的 `ai_illustrations`，
  由 `check_attribution.py` 与 `EraTheme.ERA_COVER_IMAGES` 逐张对齐（漏一张就判红）。

**同一条线的延伸**：署名不只图片——`rawfile/font/` 的两个 ttf 当时同样零记录，本轮一并补进
`attribution.json` 的 `fonts` 数组与版权页「字体」区，OFL 1.1 原文随包到 `rawfile/font/OFL-*.txt`
（过程与判据见 `PITFALLS.md` #68）。所以"版权与来源"页覆盖的是**进包的全部第三方资产**。

**未做**：版权页与灯箱图注的实机截图。本机 commit 余量 1.4 GB 而模拟器实例要 4 GB，
`Emulator.log` 报 `Commit charge is not enough!` 后自行退出（详见 `docs/PITFALLS.md` #67）；
占用来自其他会话，未代为结束。构建、十三道门禁与 73 条单测已全绿，屏上态待模拟器可起时补验。

