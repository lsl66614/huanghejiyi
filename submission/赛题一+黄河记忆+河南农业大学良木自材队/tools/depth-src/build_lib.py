# -*- coding: utf-8 -*-
"""build_lib —— 把 rawfile/sites/<id>.json 升级为深度结构，输出到 tools/depth-src/。

原则：summary / tags / relics / images / poems 及 intro/arch 中的既有关键事实一律沿用原值，
      只做扩写；events 与 tourism 由结构化数据重建。
"""
import json
import os

SRC = r"E:\ .stepclaw\huanghe-memory\app\entry\src\main\resources\rawfile\sites"
DST = r"E:\ .stepclaw\huanghe-memory\tools\depth-src"

SOURCES = {
    "dongzhou_wangcheng": [
        "《史记·周本纪》",
        "《汉书·地理志》",
        "《周礼·夏官·巾车》",
        "洛阳市文物考古研究院 东周王城遗址发掘资料",
    ],
    "shaogong_ling": [
        "郭宝钧《洛阳东周墓葬》",
        "《左传》《周礼》相关记载",
        "洛阳市文物考古研究院 洛阳古墓博物馆布展资料",
    ],
    "qicheng": [
        "《左传》僖公二十八年、襄公二年",
        "《诗经·卫风》",
        "河南省文物考古研究院 戚城遗址调查发掘资料",
    ],
    "kuo_state_city": [
        "《左传》襄公二十九年",
        "《诗经·桧风》",
        "郑州市文物考古研究院 新密市古城遗址调查报告",
    ],
    "guo_group_cemetery": [
        "《史记·虢世家》",
        "《左传》闵公二年等虢国史事记载",
        "《中国重要考古发现》 三门峡上村岭虢国墓地发掘报告",
        "国家文物局 全国十大考古新发现·上村岭虢国墓地",
    ],
    "song_ling": [
        "《宋史·礼志》陵寝制度条",
        "《东京梦华录》",
        "河南省文物考古研究院 巩义宋陵测绘与永泰陵发掘资料",
        "国务院 第二批全国重点文物保护单位名录（1982年）",
    ],
    "zhou_gucheng": [
        "《史记·魏世家》《水经注·渠水》",
        "《旧五代史·梁书》《新五代史》",
        "开封市文物考古研究所 开封城址考古发掘资料",
    ],
}


def load_original(site_id):
    with open(os.path.join(SRC, site_id + ".json"), "r", encoding="utf-8") as f:
        return json.load(f)


def build(site_id, intro, arch, events, tourism):
    old = load_original(site_id)
    assert old["id"] == site_id, (site_id, "id mismatch")
    assert len(intro) >= 300, (site_id, "intro too short", len(intro))
    assert len(arch) >= 300, (site_id, "arch too short", len(arch))
    assert len(events) == 2, (site_id, "events must be 2")
    for ev in events:
        assert len(ev["title"]) <= 30, (site_id, ev["title"])
        assert 60 <= len(ev["summary"]) <= 150, (site_id, ev["title"], "summary", len(ev["summary"]))
        for k in ("background", "process", "impact"):
            assert 120 <= len(ev[k]) <= 300, (site_id, ev["title"], k, len(ev[k]))
        assert isinstance(ev["figures"], list), (site_id, ev["title"], "figures")
        assert isinstance(ev["furtherReading"], str), (site_id, ev["title"], "furtherReading")
    g = tourism["guide"]
    for k in ("hours", "tickets", "address"):
        assert isinstance(g[k], str), (site_id, "guide", k)
    assert 120 <= len(tourism["overview"]) <= 300, (site_id, "overview", len(tourism["overview"]))
    assert 150 <= len(tourism["itinerary"]) <= 400, (site_id, "itinerary", len(tourism["itinerary"]))

    doc = {
        "id": old["id"],
        "name": old["name"],
        "city": old["city"],
        "era": old["era"],
        "site_type": old["site_type"],
        "summary": old["summary"],
        "tags": old["tags"],
        "sections": {
            "intro": intro,
            "arch": arch,
            "events": events,
            "poems": old["sections"]["poems"],
            "tourism": tourism,
        },
        "images": old["images"],
        "relics": old["relics"],
        "source": SOURCES.get(site_id, []),
    }
    os.makedirs(DST, exist_ok=True)
    out = os.path.join(DST, site_id + ".json")
    with open(out, "w", encoding="utf-8") as f:
        json.dump(doc, f, ensure_ascii=False, indent=1)
        f.write("\n")
    with open(out, "r", encoding="utf-8") as f:
        json.load(f)  # 写完即回读校验
    print("OK  %-20s events=%d intro=%d arch=%d overview=%d it=%d" % (
        site_id, len(events), len(intro), len(arch),
        len(tourism["overview"]), len(tourism["itinerary"])))