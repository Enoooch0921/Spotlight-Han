import { casual as zh } from 'chrono-node/zh';
import { casual as en } from 'chrono-node/en';

const chinese = zh.clone();
// Han uses Monday-based calendar weeks and recognises 下下週 as two weeks ahead.
chinese.parsers.unshift({
  pattern: () => /((?:下下|下|本|這|这|今|上上|上)(?:個|个)?)(?:星期|禮拜|礼拜|週|周)([一二三四五六日天末1-7])/,
  extract(context, match) {
    const weekdays = {'一':1,'二':2,'三':3,'四':4,'五':5,'六':6,'日':7,'天':7,'末':6};
    const weekday = weekdays[match[2]] || Number(match[2]);
    const shift = match[1].startsWith('下下') ? 2 : match[1].startsWith('下') ? 1 : match[1].startsWith('上上') ? -2 : match[1].startsWith('上') ? -1 : 0;
    const date = new Date(context.refDate);
    date.setDate(date.getDate() - (date.getDay() + 6) % 7 + shift * 7 + weekday - 1);
    return {year:date.getFullYear(), month:date.getMonth()+1, day:date.getDate()};
  }
});

function components(value) {
  return Object.fromEntries(['year','month','day','hour','minute','second'].map(key => [key, value.get(key) || 0]));
}
function fail(error) { return JSON.stringify({error}); }
function number(text) {
  if (text === '半') return 0.5;
  if (/^\d+(?:\.\d+)?$/.test(text)) return Number(text);
  const digits = {'零':0,'〇':0,'一':1,'二':2,'兩':2,'两':2,'三':3,'四':4,'五':5,'六':6,'七':7,'八':8,'九':9};
  let sum=0, digit=0;
  for (const c of text) {
    if (c in digits) digit=digits[c];
    else if (c==='十') {sum+=(digit||1)*10;digit=0;}
    else if (c==='百') {sum+=(digit||1)*100;digit=0;}
    else return NaN;
  }
  return sum+digit;
}
const numeral = '(?:[0-9]+(?:\\.[0-9]+)?|[零〇一二兩两三四五六七八九十百]+|半)';
const unit = '(?:小時|小时|鐘頭|钟头|分鐘|分钟|分|hours?|hrs?|minutes?|mins?)';
function seconds(amount, unit) { return number(amount) * (/小時|小时|鐘頭|钟头|hour|hr/i.test(unit) ? 3600 : 60); }
function blank(text, index, length) { return text.slice(0,index)+' '.repeat(length)+text.slice(index+length); }

export function parse(original, kind, reference) {
  if (!original.trim() || original.length>500) return fail('請輸入時間和事項，最多 200 字。');
  if (/(?:每(?:(?:隔)?[0-9一二兩两三四五六七八九十]+)?(?:個|个)?(?:天|日|週|周|星期|禮拜|礼拜|月|年)|每逢|重複|重复|\bevery\b|\brepeat(?:ing)?\b)/i.test(original)) return fail('目前支援每天、每週一個星期幾、每月一個日期；其他重複規則請在系統 App 設定。');
  let text=original, duration=null, alarmOffset=null;
  const removed=[];
  const lead = new RegExp('(?:提前|提早)\\s*('+numeral+')\\s*('+unit+')\\s*(?:('+numeral+')\\s*('+unit+'))?\\s*(?:提醒|通知)', 'i').exec(text);
  if (lead) {
    if (kind !== 'event') return fail('提醒事項使用指定時間通知；提前通知請改用行事曆。');
    alarmOffset=-(seconds(lead[1],lead[2])+(lead[3] ? seconds(lead[3],lead[4]) : 0)); removed.push([lead.index,lead[0].length]); text=blank(text,lead.index,lead[0].length);
  }
  if (kind==='event') {
    const length=new RegExp('(?:持續|持续|時長|时长|for)?\\s*('+numeral+')\\s*('+unit+')\\s*(?:(?:and)?\\s*('+numeral+')\\s*('+unit+'))?\\s*$', 'i').exec(text);
    if (length) {duration=seconds(length[1],length[2])+(length[3] ? seconds(length[3],length[4]) : 0);removed.push([length.index,length[0].length]);text=blank(text,length.index,length[0].length);}
  }
  const now=new Date(reference.year,reference.month-1,reference.day,reference.hour,reference.minute,reference.second);
  const engine=/[\u3400-\u9fff]/.test(text)?chinese:en;
  const results=engine.parse(text,now,{forwardDate:true});
  if (results.length!==1) return fail(results.length ? '找到多個時間，請一次新增一件事項。' : '尚未辨識到時間，試試「明天下午3點開會」。');
  const result=results[0];
  const allDay=!result.start.isCertain('hour');
  // A vague part of day must not silently turn into an all-day event.
  if (allDay && /上午|下午|早上|晚上|中午|凌晨|\b(?:morning|afternoon|evening|night)\b/i.test(result.text)) return fail('請補上明確時間，例如「明天下午3點」。');
  const start=components(result.start);
  let end=result.end ? components(result.end):null;
  const endText=result.text.split(/到|至|~|～|–|—/).slice(1).join(' ');
  const explicitEndDate=/(?:明天|後天|后天|今天|[0-9]{1,2}月|[0-9]{4}年|[0-9]{1,2}[/-][0-9]{1,2})/.test(endText);
  if (end && !allDay && /[\u3400-\u9fff]/.test(result.text) && !result.end.isCertain('meridiem') && !explicitEndDate && /下午|晚上|中午/.test(result.text) && start.hour>=12 && end.hour<12 && end.hour+12>start.hour) {
    // Chrono otherwise interprets 下午三點到四點 as 15:00 → next day 04:00.
    end.hour+=12; end.year=start.year;end.month=start.month;end.day=start.day;
  }
  if (end && duration!==null) return fail('已有結束時間，請移除額外的時長，避免衝突。');
  if (kind==='reminder' && end) return fail('提醒事項請只填一個通知時間；時間區間請用行事曆。');
  if (duration!==null && (!Number.isFinite(duration)||duration<=0||duration>7*86400)) return fail('行程時長必須大於 0，且不超過 7 天。');
  if (alarmOffset!==null && (!Number.isFinite(alarmOffset)||alarmOffset>0||alarmOffset< -31*86400)) return fail('提前通知時間超出範圍。');
  if (allDay && (duration!==null||alarmOffset!==null)) return fail('請加上明確時間，才能設定時長或提前通知。');
  let title=original;
  removed.push([result.index,result.text.length]);
  for(const [index,length] of removed.sort((a,b)=>b[0]-a[0])) title=title.slice(0,index)+' '+title.slice(index+length);
  title=title.replace(/^(?:請|请|幫我|帮我)?\s*(?:新增|添加|建立|安排)?\s*(?:提醒事項|提醒事项|提醒我|提醒|行事曆|行事历|行程)?[：:,，\s]*/,'').replace(/^[的，,：:\s]+|[，,：:\s]+$/g,'').replace(/\s+/g,' ').trim();
  if (!title) return fail('請補上事項名稱，例如「明天下午3點開會」。');
  // Detect leftover temporal syntax: do not bury an unsupported time in the title.
  if (/\d{1,2}[:：]\d{2}|(?:凌晨|上午|下午|晚上)\s*[0-9一二三四五六七八九十]|(?:明天|後天|后天|下週|下周)/.test(title)) return fail('時間尚未完整辨識，請簡化成一個日期與時間。');
  return JSON.stringify({title,start,end,allDay,duration,alarmOffset});
}
