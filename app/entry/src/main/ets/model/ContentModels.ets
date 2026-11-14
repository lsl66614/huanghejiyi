// entry/src/main/ets/model/ContentModels.ets
export const ERAS: string[] = ['yangshao', 'longshan', 'xiashang', 'zhou', 'hantang', 'song'];
export const CITIES: string[] = ['sanmenxia', 'luoyang', 'zhengzhou', 'kaifeng', 'puyang'];
export const SITE_TYPES: string[] = ['capital', 'burial', 'kiln', 'ancient_arch'];

export class PoemRef {
  text: string = '';
  author: string = '';
  source: string = '';
}

// 历史事件条目：赛题要求详情页含「历史事件」多层级内容，单段散文无法承载，
// 故拆为可展开的事件卡——摘要常显，背景/经过/影响/人物/延伸阅读分层展开。
export class SiteEvent {
  year: string = '';
  title: string = '';
  summary: string = '';
  background: string = '';
  process: string = '';
  impact: string = '';
  figures: string[] = [];
  furtherReading: string = '';
}

// 文旅信息：拆为概览 / 参观指引 / 行程建议三段，替代单段散文
export class TourismGuide {
  hours: string = '';
  tickets: string = '';
  address: string = '';
}

export class TourismInfo {
  overview: string = '';
  guide: TourismGuide = new TourismGuide();
  itinerary: string = '';
}

export class RelicInfo {
  id: string = '';
  siteId: string = '';
  name: string = '';
  era: string = '';
  summary: string = '';
  material: string = '';
  images: string[] = [];
}

export class SiteInfo {
  id: string = '';
  name: string = '';
  city: string = '';
  era: string = '';
  siteType: string = '';
  summary: string = '';
  tags: string[] = [];
  intro: string = '';
  archaeology: string = '';
  events: SiteEvent[] = [];
  poems: PoemRef[] = [];
  tourism: TourismInfo = new TourismInfo();
  images: string[] = [];
  relics: RelicInfo[] = [];
}

// 主题路线：不新建数据表，只是一份人工排过序的遗址清单。
// note 回答的是「为什么这一站排在这里」——没有这句，路线就退化成
// 一串带序号的列表，用户没有理由按顺序读。
export class RouteStop {
  siteId: string = '';
  note: string = '';
}

export class RouteInfo {
  id: string = '';
  title: string = '';
  subtitle: string = '';
  era: string = '';
  duration: string = '';
  stops: RouteStop[] = [];
}
