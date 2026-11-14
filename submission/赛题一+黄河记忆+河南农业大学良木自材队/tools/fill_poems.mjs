// tools/fill_poems.mjs —— 为 42 处遗址的 sections.poems 填充公有领域历代名篇（可重复执行，幂等）
// 编纂原则：真句、真作者、真出处；按年代+地域匹配；史前遗址以咏黄河/怀古诗补位，不杜撰。
// 运行：node tools/fill_poems.mjs
import { readFileSync, writeFileSync, readdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(join(dirname(fileURLToPath(import.meta.url)), '..'));
const DIR = join(ROOT, 'app/entry/src/main/resources/rawfile/sites');

function resolve(p) { return p; }

// 诗库（节选均为通行本确定文本）
const P = {
  guanquelou: { text: '白日依山尽，黄河入海流。欲穷千里目，更上一层楼。', author: '王之涣', source: '《登鹳雀楼》' },
  qiangjinjiu: { text: '君不见黄河之水天上来，奔流到海不复回。', author: '李白', source: '《将进酒》' },
  langtaosha: { text: '九曲黄河万里沙，浪淘风簸自天涯。如今直上银河去，同到牵牛织女家。', author: '刘禹锡', source: '《浪淘沙·其一》' },
  liangzhouci: { text: '黄河远上白云间，一片孤城万仞山。羌笛何须怨杨柳，春风不度玉门关。', author: '王之涣', source: '《凉州词》' },
  changhe: { text: '黄河落天走东海，万里写入胸怀间。', author: '李白', source: '《赠裴十四》' },
  xuanniao: { text: '天命玄鸟，降而生商。宅殷土芒芒。古帝命武汤，正域彼四方。', author: '《诗经·商颂》', source: '《玄鸟》' },
  changfa: { text: '洪水芒芒，禹敷下土方。外大国是疆，幅陨既长。', author: '《诗经·商颂》', source: '《长发》' },
  zijin: { text: '青青子衿，悠悠我心。纵我不往，子宁不嗣音？', author: '《诗经·郑风》', source: '《子衿》' },
  zhenwei: { text: '溱与洧，方涣涣兮。士与女，方秉蕑兮。', author: '《诗经·郑风》', source: '《溱洧》' },
  qiyu: { text: '瞻彼淇奥，绿竹猗猗。有匪君子，如切如磋，如琢如磨。', author: '《诗经·卫风》', source: '《淇奥》' },
  shuli: { text: '彼黍离离，彼稷之苗。行迈靡靡，中心摇摇。知我者谓我心忧，不知我者谓我何求。悠悠苍天，此何人哉？', author: '《诗经·王风》', source: '《黍离》' },
  beishan: { text: '溥天之下，莫非王土；率土之滨，莫非王臣。', author: '《诗经·小雅》', source: '《北山》' },
  wenwang: { text: '文王在上，於昭于天。周虽旧邦，其命维新。', author: '《诗经·大雅》', source: '《文王》' },
  feifeng: { text: '匪风发兮，匪车偈兮。顾瞻周道，中心怛兮。', author: '《诗经·桧风》', source: '《匪风》' },
  luochengdi: { text: '谁家玉笛暗飞声，散入春风满洛城。此夜曲中闻折柳，何人不起故园情。', author: '李白', source: '《春夜洛城闻笛》' },
  guguluoyang: { text: '烟愁雨啸黍华生，宫阙簪裳旧帝京。若问古今兴废事，请君只看洛阳城。', author: '司马光', source: '《过故洛阳城》' },
  shouhenan: { text: '剑外忽传收蓟北，初闻涕泪满衣裳。却看妻子愁何在，漫卷诗书喜欲狂。', author: '杜甫', source: '《闻官军收河南河北》' },
  beimang: { text: '洛阳北门北邙道，丧车辚辚入秋草。', author: '张籍', source: '《北邙行》' },
  tongguan: { text: '终古高云簇此城，秋风吹散马蹄声。河流大野犹嫌束，山入潼关不解平。', author: '谭嗣同', source: '《潼关》' },
  bianhequ: { text: '汴水东流无限春，隋家宫阙已成尘。行人莫上长堤望，风起杨花愁杀人。', author: '李益', source: '《汴河曲》' },
  bianhuaigu: { text: '尽道隋亡为此河，至今千里赖通波。若无水殿龙舟事，共禹论功不较多。', author: '皮日休', source: '《汴河怀古》' },
  suidiliu: { text: '西自黄河东至淮，绿阴一千三百里。大业末年春暮月，柳色如烟絮如雪。', author: '白居易', source: '《隋堤柳》' },
  bianjing1: { text: '辇毂繁华事可伤，师师垂老过湖湘。缕衣檀板无颜色，一曲当时动帝王。', author: '刘子翚', source: '《汴京纪事》' },
  bianjing2: { text: '梁园歌舞足风流，美酒如刀解断愁。忆得少年多乐事，夜深灯火上樊楼。', author: '刘子翚', source: '《汴京纪事》' }
};

// site id → 诗（按时代与地域归属）
const MAP = {
  // 仰韶（史前，以咏黄河中游名篇补位）
  bancun: ['guanquelou'],
  yangshao_village: ['langtaosha'],
  miaodigou: ['qiangjinjiu'],
  mianchi_yangshao: ['liangzhouci'],
  suoyang: ['changhe'],
  qingtai: ['guanquelou'],
  xinzhai: ['changhe'],
  xishuipo: ['guanquelou'],
  puyang_xian: ['qiangjinjiu'],
  kaifeng_xian: ['langtaosha'],
  // 龙山
  dahecun: ['guanquelou'],
  kaifeng_longshan: ['qiangjinjiu'],
  qiji: ['liangzhouci'],
  wangchenggang: ['changfa'],            // 王城岗传为禹都阳城，《长发》咏禹敷土
  wanwang_wangwan: ['changhe'],
  // 夏商
  erlitou: ['changfa'],                   // 二里头=夏中晚期都城，取《长发》禹夏之句
  yanshi_shangcheng: ['xuanniao'],
  zhengzhou_shangcheng: ['xuanniao'],
  duling_fangding: ['xuanniao'],
  xiaoshuangqiao: ['changfa'],
  diqiu: ['xuanniao'],
  qifeng_gucheng: ['zhenwei'],            // 启封本春秋郑地
  // 周
  dongzhou_wangcheng: ['shuli'],          // 《王风》为东迁洛邑之诗
  shaogong_ling: ['beishan'],
  guo_group_cemetery: ['wenwang'],
  kuo_state_city: ['feifeng'],           // 桧=郐，《桧风》即郐国诗
  qicheng: ['qiyu'],                      // 戚城为卫邑，《卫风》淇水卫地
  zhou_gucheng: ['bianhequ'],             // 汴州城临汴河，条目下探至唐
  // 汉唐
  han_tongguan: ['tongguan'],
  hanwei_luoyangcheng: ['guguluoyang'],
  hanwei_luoyangcheng_taiji: ['shouhenan'],
  yanshi: ['luochengdi'],
  xizhucun_caozhong_m: ['beimang'],
  xingyang_gucheng: ['langtaosha'],
  huatigou: ['suidiliu'],
  huanghe_gendi: ['guanquelou'],
  // 宋
  dongjing: ['bianhuaigu'],               // 州桥及汴河遗址
  jingjiugong: ['bianjing1'],
  kaita: ['bianjing2'],
  gongxian_yao: ['liangzhouci'],
  song_ling: ['beimang'],                 // 巩义宋陵近北邙陵墓带
  tiejun_miao: ['guanquelou']
};

const files = readdirSync(DIR).filter((f) => f.endsWith('.json'));
let touched = 0;
const missing = [];
for (const f of files) {
  const p = join(DIR, f);
  const j = JSON.parse(readFileSync(p, 'utf8'));
  const keys = MAP[j.id];
  if (keys === undefined) { missing.push(j.id); continue; }
  const poems = keys.map((k) => P[k]);
  const before = JSON.stringify(j.sections.poems);
  j.sections.poems = poems;
  if (JSON.stringify(poems) !== before) {
    writeFileSync(p, JSON.stringify(j, null, 1) + '\n', 'utf8');
    touched++;
  }
}
console.log(`poems filled: ${touched}/${files.length} files rewritten`);
if (missing.length) { console.error('UNMAPPED:', missing.join(', ')); process.exit(1); }
