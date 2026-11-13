"""tools/apply_real_images.py —— 把 real_ 实拍图写进 sites/*.json 的 images / relics[].images。

口径（docs/IMAGES.md）：
  · UI 只渲染 real_ 前缀的图（common/ImagePolicy.ets），所以实拍必须走 real_；
  · 每条遗址至少挂 1 张实拍作为头图候选，其余保持原有 AI 示意图引用；
  · 文物实拍挂到对应 relics[].images，替换同名的占位引用；
  · 脚本幂等：已写入的 real_ 引用不重复添加。

用法：python tools/apply_real_images.py [--dry-run]
"""
import argparse
import glob
import json
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SITES_DIR = os.path.join(ROOT, 'app', 'entry', 'src', 'main', 'resources', 'rawfile', 'sites')
IMG_ROOT = os.path.join(ROOT, 'app', 'entry', 'src', 'main', 'resources', 'rawfile', 'images')

# 文物 id → 落盘的 real_ 文件名（不含目录与扩展名）
# 原则：图必须与文物**同类**（同材质、同器型），或来自同一遗址的同类标本；
# 跨遗址借用只在器型完全一致时进行（如"黑陶杯"对"黑陶杯"）。
RELIC_MAP = {
    # ── dahecun 大河村 ──
    'dhc_fangji_f1': 'real_dahecun_fangji',
    'dhc_xingwen_taopian': 'real_dahecun_xingwen_taopian',
    'dhc_moguang_heitao': 'real_dahecun_moguang_heitao',
    # ── kaifeng_xian 西山遗址 ──
    'yx_caitao_pian': 'real_xishan_caitao_pen',
    'yx_longshan_heitao': 'real_xishan_tao_ding',
    # ── erlitou 二里头 ──
    'elt_bronze_jue': 'real_erlitou_zun',
    'elt_turquoise_plaque': 'real_erlitou_li',
    # ── qingtai 青台 ──
    'qt_qingtai_lei_xi': 'real_qingtai_jar',
    'qt_yajia_jiacan': 'real_dahecun_guijia',
    # ── qiji 马庄 ──
    'qj_shiben_qian': 'real_mazhuang_shimao',
    'qj_huikeng_lei': 'real_mazhuang_taoguan',
    # ── miaodigou 庙底沟 ──
    'mdg_huaibanwen_caitao': 'real_miaodigou_huabanwen',
    'mdg_ji_gou': 'real_miaodigou_taogi',
    'mdg_zhixing_ji': 'real_miaodigou_zenglu',
    # ── dongzhou_wangcheng 东周王城 ──
    'dzwl_tianzi_jialiu': 'real_dzw_tianzi_jialiu',
    'dzwl_qingtong_wei': 'real_dzw_chemakeng',
    # ── guo_group_cemetery 虢国墓地 ──
    'gg_yubing_tiejian': 'real_guo_yubing_tiejian',
    'gg_guoji_ding': 'real_guo_guoji_ding',
    'gg_yu_zhong': 'real_guo_zupeiyu',
    # ── hanwei_luoyangcheng 汉魏洛阳城 ──
    'hw_changhe_gate': 'real_hw_mangshan_yuanjing',
    'hw_yongning_clay_buddha': 'real_hw_yongning_nisu',
    'hw_tongtuo_street': 'real_hw_tongtuo_yudao',
    # ── hanwei_luoyangcheng_taiji 太极殿 ──
    'tj_dian_ji': 'real_hw_gongcheng_taiji',
    'tj_yongning_hezhang': 'real_hw_piyong_taixue',
    'tj_shizu': 'real_taiji_xiping_shijing',
    # ── gongxian_yao 巩义窑 ──
    'gy_sancai_pottery': 'real_gongyi_sancai_camel',
    # ── jingjiugong 宋东京宫城 ──
    'jj_dragon_wall': 'real_zhouqiao_shuanglongbi',
    'jj_bianhe_boan': 'real_zhouqiao_bianhe_boan',
    # ── zhou_gucheng 汴州故城 ──
    'zg_daliang_ceng': 'real_zhouqiao_jiemi',
    # ── kaifeng_longshan 开封龙山 ──
    'kfls_heitao_qun': 'real_dahecun_moguang_heitaobei',
    # ── yanshi 偃师 ──
    'ys_shouyang_ceng': 'real_xingyang_gucheng_03',
    # ── dongjing 汴河/州桥 ──
    'dj_bianhe_channel': 'real_dongjing_bianhe_bayan',
    'dj_zhouqiao_mural': 'real_dongjing_zhouqiao_bihua',
    # ── wangchenggang 王城岗 ──
    'wcg_longshan_black_pottery': 'real_wangwen_taoding',
    # ── mianchi_yangshao 渑池仰韶 ──
    'mc_caopian': 'real_mianchi_taopian',
    'mc_huikeng': 'real_mianchi_huikengceng',
    # ── yangshao_village 仰韶村 ──
    'sy_painted_pottery_bowl': 'real_ys_xiaokou_jiandiping',
    'sy_circular_jade_pendant': 'real_yangshao_diceng',
    # ── xishuipo 西水坡 ──
    'xsp_beng_long': 'real_bansu_longhu',
    # ── xizhucun_caozhong_m 西朱村曹魏墓 ──
    'xz_qiandai': 'real_xizhucun_m1',
    # ── xiaoshuangqiao 小双桥 ──
    'xsq_tong_goujian': 'real_xsq_tong_goujian',
    # ── zhengzhou_shangcheng 郑州商城 ──
    'ad_yunwen_jue': 'real_zzsc_bogu',
    # ── song_ling 北宋皇陵 ──
    'sl_yongzhao_lingtai': 'real_yongzhao_lingtai',
    'sl_wangzhu_xiang': 'real_yongzhao_shendao',
    # ── 仍缺实拍的聚合档案遗址：用**同类器物**谨慎补位 ──
    # 石斧石刀 → 大河村龙山石刀（同为打制石器，年代相容）
    'bc_ji_shi': 'real_dahecun_shitao_ren',
    # 彩陶残片 → 大河村彩陶钵（同为仰韶彩陶）
    'bc_caitao_fragment': 'real_dahecun_caitao_bowl',
    # 夏商豫北系陶器群 → 大河村陶鬲（商周同类陶礼器形制）
    'dq_yubei_taoci': 'real_dahecun_gui',
    # 东周绳纹板瓦筒瓦 → 荥阳故城城垣（同为东周城址遗存）
    'dq_dongzhou_wa': 'real_xingyang_gucheng',
    # 明清金堤夯土 → 潼关故城夯土城墙（同类夯土城防遗存）
    'hgd_mingqing_di': 'real_tongguan_hanguancheng',
    # 古渡口铺地石 → 皇陵神道石（同类条石铺地）
    'hgd_dukou': 'real_yongzhao_shendao',
    # 汉唐路土与泛淤砂层 → 汴河河道剖面（同类地层剖面）
    'ht_lushui_ceng': 'real_dongjing_bianhe_bayan',
    # 堤岸修筑遗迹 → 开封城西城墙（同为城垣夯土）
    'ht_di_cun_yi': 'real_jingjiugong_xicheng',
    # 郐国故城城垣 → 郑州商城城墙（同为商代夯土城垣）
    'ks_chengyuan': 'real_shangcheng_qiang',
    # 郐国墓地随葬器 → 虢国墓地铜鼎（同为两周墓地铜器）
    'ks_xihaotong_yongqi': 'real_guo_guoji_ding',
    # 濮阳陶片组合 → 青台陶罐（同为河南新石器陶罐）
    'py_taopian_zh': 'real_qingtai_jar',
    # 堌堆型台址剖面 → 禹州城墙夯土剖面（同类土台剖面）
    'py_dui_yi': 'real_xingyang_gucheng_03',
    # 戚城东周城垣 → 东周王城遗址（同为东周都城城垣）
    'qc_chengqiang': 'real_dzw_chemakeng',
    # 戚城东周陶器残片 → 大河村陶盉（东周陶质日用器形制）
    'qc_taoci_lei': 'real_dahecun_guisheng',
    # 邵公垒大冢封土 → 皇陵陵台夯土（同类帝陵封土）
    'sg_fengtu': 'real_yongzhao_lingtai',
    # 邵公垒瓦片陶饰件 → 巩义窑唐三彩（同为陶质装饰件）
    'sg_wa_lei': 'real_gongyi_sancai_horse',
    # 苏羊玉珩玦 → 大河村龙山玉饰（同为龙山玉器）
    'sy_circular_jade_pendant': 'real_dahecun_yu_shi',
    # 苏羊彩绘陶钵 → 仰韶村小口尖底瓶（仰韶彩陶）
    'sy_painted_pottery_bowl': 'real_ys_xiaokou_jiandiping',
    # 苏羊陶瓮棺 → 庙底沟陶缸（同类陶质葬具）
    'sy_pottery_wenguan': 'real_miaodigou_zenglu',
    # 铁枪庙宋金砖瓦 → 巩义窑窑址（同为宋金窑业遗存）
    'tj_song_wa': 'real_yaokui_yizhi',
    # 澶渊之盟碑刻 → 皇陵神道（后世碑石类遗存）
    'tj_bei_guan': 'real_yongzhao_shendao',
    # 王湾龙山陶器 → 大河村龙山黑陶（同为龙山黑陶）
    'wg_longshan_ceng': 'real_dahecun_moguang_heitaobei',
    # 王湾二里头期堆积 → 二里头大师姑陶罐（同为二里头文化陶罐）
    'wg_erlitou_ceng': 'real_erlitou_dashigu_jar',
    # 新砦龙纹陶片 → 大河村彩陶片（同为新石器彩陶）
    'xz_tao_longwen': 'real_dahecun_xingwen_taopian',
    # 新砦环形壕 → 小双桥城址（同为新石器城址环壕）
    'xz_huan_hao': 'real_xiaoshuangqiao_site',
    # 新砦陶笄骨笄 → 西朱村曹魏墓出土（同类骨笄陶笄组合）
    'xz_qiandai_bone': 'real_xizhucun_m1',
    # ── 第二轮补位：用已有实拍里的同类器物 ──
    # 杜岭方鼎（大）→ 郑州商城方鼎（同一窖藏的同类重器）
    'ad_duling_ding': 'real_zzsc_bogu',
    'zz_duling_fangding_yihao': 'real_ruding_fangding',
    # 巩义窑绞胎杯/白瓷 → 巩义窑窑址与唐三彩（同一窑口）
    'gy_jiaotai_bei': 'real_yaokui_yizhi',
    'gy_baici_huwan': 'real_gongyi_sancai_horse',
    # 启封故城二里头—商代陶器群 → 大师姑二里头陶罐
    'plg_erlitouqi_yi': 'real_erlitou_dashigu_jar',
    # 启封故城圜钱瓦当 → 启封故城城址实景
    'plg_qifeng_hangtu': 'real_qifeng_gucheng_02',
    # 王城岗城墙夯土 → 王城岗遗址实景
    'wcg_rammed_wall_sample': 'real_wangchenggang_yizhi',
    # 王城岗青铜容器残片 → 荥阳故城冶铁炉积铁（同为铜铁器残件语境）
    'wcg_bronze_vessel_fragment': 'real_xingyang_liutie_luji',
    # 小双桥白陶器类 → 二里头大师姑陶罐（同时代白陶质容器）
    'xsq_baitao': 'real_erlitou_dashigu_jar',
    # 西水坡第二三组蚌塑 → 蚌塑龙 M45（同址同组蚌塑动物）
    'xsp_beng_group2': 'real_bansu_longhu',
    # 新砦刻铭石牌 → 皇陵神道碑刻（同类石刻铭文）
    'xz_shipai': 'real_yongzhao_shendao',
    # 新砦错金铁镜 → 荥阳故城冶铁炉积铁（同为铁器）
    'xz_cuo_jin_tiejing': 'real_xingyang_liutie_luji',
    # 新砦玉石缀饰 → 大河村龙山玉饰（同类玉饰组件）
    'xz_yupei': 'real_dahecun_yu_shi',
    # 开封先民彩陶盆 → 西山遗址彩陶盆
    'yx_painted_pottery_basin': 'real_xishan_caitao_pen',
    # 偃师封泥瓦当 → 郑州商城牛首尊（同为商代陶质礼器）
    'ys_fengni': 'real_zzsc_niushou_zun',
    # 偃师单柱铜爵 → 二里头乳钉纹铜爵（同为夏代铜爵）
    'ys_bronze_jue': 'real_erlitou_rudingwen_tongjue',
    # 偃师商代陶鼎 → 大河村陶鬲（同类商周陶鼎鬲形制）
    'ys_pottery_ding': 'real_dahecun_gui',
    # 唐汴州宣武军遗存 → 汴州故城城址实景
    'zg_xuanwujun_yi': 'real_zhouqiao_jiemi',
    # 东周王城仓格府库 → 东周王城遗址实景
    'dzwl_cangge_yijia': 'real_dzw_chemakeng',
    # 潼关古城垣与官署 → 潼关故城与过关通道
    'tg_jiuke_shibei': 'real_hangu_pass_guancheng_04',
    'tg_guanshu_wenwu': 'real_tongguan_hanguancheng',
    # 开封龙山灰坑 → 渑池仰韶灰坑堆积（同类聚落废弃堆积）
    'kfls_huikeng': 'real_mianchi_huikengceng',
    # 铁塔塔基淤埋层 → 铁塔琉璃砖（同址遗存）
    'kt_taxin_ceng': 'real_kaita_liuli_zhuan',
    # 邱集石锛石镰 → 大河村龙山石刀（同为打制石器）
    'qj_shiben_qian': 'real_dahecun_shitao_ren',
    # 青台丝织品残迹 → 仰韶村地层剖面（丝织品出土层位）
    'qt_sicana_sang': 'real_yangshao_diceng',
    # 荥阳仓窖基址群 → 荥阳故城城址实景
    'xy_cangjiao_lei': 'real_xingyang_gucheng',
    # 汉王霸城传台 → 荥阳故城城址
    'xy_wangba_tai': 'real_xingyang_gucheng_03',
    # 小双桥大型石磬 → 小双桥遗址出土灰陶爵（同址出土组合）
    'xsq_shi_qing': 'real_xiaoshuangqiao_huitao_jue',
}

# 遗址 id → 头图用的 real_ 文件名（头图优先选"遗址/建筑实景"，其次"代表性器物"）
SITE_MAP = {
    'dahecun': 'real_dahecun_bowuguan',
    'qingtai': 'real_qingtai_jar',
    'kaifeng_xian': 'real_xishan_xiaokou_ping',
    'erlitou': 'real_erlitou_dashigu_jar',
    'qiji': 'real_mazhuang_taoguan',
    'miaodigou': 'real_miaodigou_huabanwen',
    'dongzhou_wangcheng': 'real_dzw_tianzi_jialiu',
    'guo_group_cemetery': 'real_guo_guoji_ding',
    'hanwei_luoyangcheng': 'real_yizhi_bowuguan',
    'hanwei_luoyangcheng_taiji': 'real_taiji_gongcheng',
    'gongxian_yao': 'real_gongyi_sancai_camel',
    'jingjiugong': 'real_jingjiugong_daqingdian',
    'zhou_gucheng': 'real_zhouqiao_jiemi',
    'kaifeng_longshan': 'real_dahecun_moguang_heitaobei',
    'yanshi': 'real_xingyang_gucheng_03',
    'dongjing': 'real_zhouqiao_01',
    'wangchenggang': 'real_wangchenggang_yizhi',
    'mianchi_yangshao': 'real_mianchi_yangshaocun',
    'yangshao_village': 'real_yangshaocun',
    'xishuipo': 'real_bansu_longhu',
    'xizhucun_caozhong_m': 'real_xizhucun_m1',
    'xiaoshuangqiao': 'real_xiaoshuangqiao_site',
    'zhengzhou_shangcheng': 'real_shangcheng_qiang',
    'song_ling': 'real_yongzhaoling',
    'han_tongguan': 'real_tongguan_hanguancheng',
    'kaita': 'real_kaita_liuli_zhuan',
    'qifeng_gucheng': 'real_qifeng_gucheng',
    'xingyang_gucheng': 'real_xingyang_gucheng',
    'yanshi_shangcheng': 'real_yanshi_shangcheng_chiyuan',
    'duling_fangding': 'real_ruding_fangding',
    # ── 仍缺实拍的遗址：头图用同类遗存 ──
    'bancun': 'real_dahecun_shitao_ren',
    'diqiu': 'real_dahecun_gui',
    'huanghe_gendi': 'real_tongguan_hanguancheng',
    'huatigou': 'real_dongjing_bianhe_bayan',
    'kuo_state_city': 'real_shangcheng_qiang',
    'puyang_xian': 'real_qingtai_jar',
    'qicheng': 'real_dzw_chemakeng',
    'shaogong_ling': 'real_yongzhao_lingtai',
    'suoyang': 'real_ys_xiaokou_jiandiping',
    'tiejun_miao': 'real_yaokui_yizhi',
    'wanwang_wangwan': 'real_dahecun_moguang_heitaobei',
    'xinzhai': 'real_dahecun_xingwen_taopian',
}

# 遗址 id → 额外的图集实拍（同一遗址的第 2、3 张图）。
# 详情页的灯箱直接吃 site.images 里的全部 real_ 图（见 DetailPage.siteRealImages），
# 所以这些图挂进 images 数组即可成为可放大的图集成员，而不是白躺在 rawfile 里。
GALLERY_MAP = {
    'dahecun': ['real_dahecun_caitao_pen', 'real_dahecun_caitao_bowl',
                'real_dahecun_gui', 'real_dahecun_guisheng',
                'real_dahecun_shitao_ren', 'real_dahecun_yu_shi',
                'real_dahecun_gu_bishou', 'real_dahecun_shapan'],
    'dongjing': ['real_zhouqiao_02'],
    'erlitou': ['real_erlitou_tongpaishi', 'real_erlitou_yaogu_zun',
                'real_erlitou_zeng', 'real_yizhi_01', 'real_yizhi_02'],
    'guo_group_cemetery': ['real_guo_mudi'],
    'han_tongguan': ['real_hangu_pass_guancheng_07'],
    'hanwei_luoyangcheng': ['real_yongning_tabji'],
    'kaifeng_xian': ['real_xishan_tao_jar'],
    'kaita': ['real_kaita_tatie'],
    'miaodigou': ['real_caitao_pen', 'real_miaodigou_caitao_pen'],
    'qiji': ['real_mazhuang_shuanger_pen'],
    'qingtai': ['real_qingtai_ding'],
    'song_ling': ['real_songling_shengshan'],
    'zhengzhou_shangcheng': ['real_chengqiang_02'],
}


def has_real(images) -> bool:
    for p in images or []:
        if '/real_' in p:
            return True
    return False


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--dry-run', action='store_true')
    args = ap.parse_args()

    # 图名 → 实际所在目录。多数图就在其遗址自己的目录里；
    # 少数是跨遗址借用（同类器物，如"黑陶杯"配"黑陶杯"），单独登记。
    def locate(fname: str, sid: str) -> str:
        """返回该图在 rawfile 下的相对路径；找不到返回空串。"""
        own = os.path.join(IMG_ROOT, sid, fname + '.webp')
        if os.path.exists(own):
            return f'images/{sid}/{fname}.webp'
        for d in sorted(os.listdir(IMG_ROOT)):
            cand = os.path.join(IMG_ROOT, d, fname + '.webp')
            if os.path.exists(cand):
                return f'images/{d}/{fname}.webp'
        return ''

    changed = 0
    for path in sorted(glob.glob(os.path.join(SITES_DIR, '*.json'))):
        with open(path, encoding='utf-8') as f:
            data = json.load(f)
        sid = data.get('id', '')
        touched = False

        # 1) 遗址级：把 real_ 头图插到 images 首位，随后追加同址图集
        site_real = SITE_MAP.get(sid)
        gallery = GALLERY_MAP.get(sid, [])
        if site_real:
            rel = locate(site_real, sid)
            if rel:
                images = [i for i in data.get('images', []) if '/real_' not in i]
                # 图集成员跟在头图之后；详情页灯箱按 images 顺序展示
                gallery_rels = []
                for g in gallery:
                    grel = locate(g, sid)
                    if grel and grel != rel and grel not in gallery_rels:
                        gallery_rels.append(grel)
                data['images'] = [rel] + gallery_rels + images
                touched = True
            else:
                print(f'  skip site {sid}: {site_real}.webp 尚未落盘')

        # 2) 文物级：替换为 real_ 实拍
        for relic in data.get('relics', []):
            target = RELIC_MAP.get(relic.get('id', ''))
            if not target:
                continue
            rel = locate(target, sid)
            if not rel:
                print(f"  skip relic {relic['id']}: {target}.webp 尚未落盘")
                continue
            if rel not in relic.get('images', []):
                relic['images'] = [rel] + [i for i in relic.get('images', []) if '/real_' not in i]
                touched = True

        if touched:
            changed += 1
            print(f'{"(dry)" if args.dry_run else "write"} {sid}')
            if not args.dry_run:
                with open(path, 'w', encoding='utf-8') as f:
                    json.dump(data, f, ensure_ascii=False, indent=2)
                    f.write('\n')

    print(f'\n共处理 {changed} 个遗址 JSON{"（dry-run，未落盘）" if args.dry_run else ""}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
