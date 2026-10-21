//+------------------------------------------------------------------+
//|                                                     SMCZones.mq5 |
//|                                      Copyright 2026, Allan Niñal |
//|                                  https://www.allanninal.dev/mql5 |
//+------------------------------------------------------------------+
//| Smart-money concepts zones: order blocks, fair value gaps,       |
//| BOS / CHoCH, optional liquidity sweeps and session filter, and   |
//| optional zones from a higher timeframe.                          |
//| Every zone is decided from closed bars only: its creation and    |
//| its mitigation never change afterwards, so nothing appears or    |
//| disappears after the bar closed. Rules:                          |
//|  swing     N bars each side, known N bars later                  |
//|  BOS/CHoCH a close beyond the last unbroken swing; CHoCH when    |
//|            it reverses the previous break                       |
//|  order blk the last candle against the move at the start of the  |
//|            leg that broke the swing                             |
//|  FVG       a three-candle gap of at least k x ATR                |
//|  mitigated chosen rule: touch, midpoint, far-edge wick, or a     |
//|            close beyond the far edge                             |
//| An indicator, not a trading system: it draws and alerts only.    |
//+------------------------------------------------------------------+
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0 (see LICENSE)
#property copyright "Copyright 2026, Allan Niñal <https://www.allanninal.dev/mql5>"
#property link      "https://www.allanninal.dev/mql5"
#property version   "1.01"
#property description "Smart-money zones: order blocks, fair value gaps, BOS/CHoCH, optional sweeps, session filter and higher-timeframe zones."
#property description "Non-repainting: zones are decided from closed bars and never change afterwards. Alerts for new, touched and mitigated zones."
#property indicator_chart_window
#property indicator_buffers 16
#property indicator_plots   16

#include "SmcEngine.mqh"

enum ENUM_SMCZ_MIT
  {
   SMCZ_MIT_TOUCH=0,    // Touch: a wick reaches the near edge
   SMCZ_MIT_MID=1,      // Midpoint: a wick reaches the middle
   SMCZ_MIT_WICK=2,     // Far edge, wick: a wick reaches the far edge
   SMCZ_MIT_CLOSE=3     // Far edge, close: a bar closes beyond the far edge
  };

input group "Structure"
input int           InpSwing     = 3;               // Swing strength, bars on each side
input int           InpATR       = 14;              // ATR period
input group "Order blocks"
input bool          InpShowOB    = true;            // Draw order blocks
input ENUM_SMCZ_MIT InpOBMit     = SMCZ_MIT_CLOSE;  // Order block is mitigated when
input group "Fair value gaps"
input bool          InpShowFVG   = true;            // Draw fair value gaps
input double        InpFVGMin    = 0.20;            // Minimum gap, x ATR
input ENUM_SMCZ_MIT InpFVGMit    = SMCZ_MIT_WICK;   // Gap is mitigated when
input group "Liquidity sweeps"
input bool          InpShowSweeps = false;          // Mark liquidity sweeps
input int           InpSweepLook = 60;              // Swing looked back, bars
input double        InpSweepMin  = 0.10;            // Wick beyond the swing, min x ATR
input group "Session filter"
input bool          InpUseSession = false;          // Only create zones and sweeps in the session
input int           InpSessStart = 7;               // Session start, server hour
input int           InpSessEnd   = 17;              // Session end, server hour (exclusive)
input group "Higher timeframe"
input ENUM_TIMEFRAMES InpHTF     = PERIOD_CURRENT;  // Also draw zones of this timeframe (current = off)
input group "Display"
input bool          InpShowStruct = true;           // Draw BOS / CHoCH lines
input bool          InpShowMitigated = false;       // Keep mitigated zones, up to their mitigation bar
input int           InpDrawBars  = 1000;            // Draw zones created within this many bars
input int           InpMaxZones  = 80;              // Draw at most this many zones (newest first)
input int           InpExtendBars = 12;             // Extend live zones this many bars past the last bar
input bool          InpFill      = true;            // Fill the zones
input color         InpClrOBBull = 6057759;    // Bullish order block
input color         InpClrOBBear = 3421312;    // Bearish order block
input color         InpClrFVGBull = 9198638;   // Bullish gap
input color         InpClrFVGBear = 2516108;  // Bearish gap
input color         InpClrHTF    = 7888992;    // Higher-timeframe zones (outline colour)

#include "SignalAlerts.mqh"

input group "Alert events"
input bool          InpAlNew     = true;            // Alert: new order block or gap
input bool          InpAlTouch   = true;            // Alert: price touches a live zone
input bool          InpAlMit     = false;           // Alert: a zone is mitigated
input bool          InpAlStruct  = true;            // Alert: BOS / CHoCH
input bool          InpAlSweep   = false;           // Alert: liquidity sweep

const string PRODUCT="SMC Zones";
const string PFX="SMCZ_";

class CBuf { public: double v[]; };
CBuf g_buf[B_COUNT];
CSmcEngine g_eng,g_htf;
double g_out[];
datetime g_htf_last=0;
int g_draw_stamp=-1;
bool g_no_draw=false;                            // set in OnInit: tester without visual mode

void Configure(CSmcEngine &e)
  {
   e.swing=InpSwing;
   e.atr_period=InpATR;
   e.fvg_min=InpFVGMin;
   e.ob_mit=(int)InpOBMit;
   e.fvg_mit=(int)InpFVGMit;
   e.sweep_look=InpSweepLook;
   e.sweep_min=InpSweepMin;
   e.use_session=InpUseSession;
   e.s_start=InpSessStart;
   e.s_end=InpSessEnd;
  }

int OnInit()
  {
   if(InpSwing<1 || InpATR<1 || InpFVGMin<0 || InpSweepLook<1 || InpSweepMin<0 || InpDrawBars<1 || InpMaxZones<0 ||
      InpSessStart<0 || InpSessStart>23 || InpSessEnd<0 || InpSessEnd>24)
     {
      Print("SMC Zones: check the inputs (swing and ATR period at least 1, hours 0-23)");
      return(INIT_PARAMETERS_INCORRECT);
     }
   string names[B_COUNT]={"OB bull top","OB bull bottom","OB bear top","OB bear bottom","FVG bull top","FVG bull bottom",
                          "FVG bear top","FVG bear bottom","Structure (1 BOS, 2 CHoCH, sign = direction)","Broken level",
                          "Sweep of a low","Sweep of a high","Zones mitigated","Zones touched","Live bullish zones","Live bearish zones"};
   ArrayResize(g_out,B_COUNT);
   for(int k=0; k<B_COUNT; k++)
     {
      SetIndexBuffer(k,g_buf[k].v,INDICATOR_DATA);
      PlotIndexSetInteger(k,PLOT_DRAW_TYPE,DRAW_NONE);
      PlotIndexSetDouble(k,PLOT_EMPTY_VALUE,EMPTY_VALUE);
      PlotIndexSetString(k,PLOT_LABEL,names[k]);
     }
   Configure(g_eng);
   Configure(g_htf);
   g_eng.Reset();
   g_htf.Reset();
   g_htf_last=0;
   g_draw_stamp=-1;
   g_no_draw=(MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE));
   IndicatorSetString(INDICATOR_SHORTNAME,"SMC Zones");
   IndicatorSetInteger(INDICATOR_DIGITS,_Digits);
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0,PFX);
   ChartRedraw();
  }

//--- one rectangle
void Rect(const string name,const datetime t1,const double top,const datetime t2,const double bot,const color clr,
          const bool fill,const string tip)
  {
   if(ObjectCreate(0,name,OBJ_RECTANGLE,0,t1,top,t2,bot))
     {
      ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
      ObjectSetInteger(0,name,OBJPROP_FILL,fill);
      ObjectSetInteger(0,name,OBJPROP_BACK,true);
      ObjectSetInteger(0,name,OBJPROP_WIDTH,1);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
      ObjectSetString(0,name,OBJPROP_TOOLTIP,tip);
     }
  }

void Seg(const string name,const datetime t1,const double p1,const datetime t2,const double p2,const color clr,
         const ENUM_LINE_STYLE style,const string tip)
  {
   if(ObjectCreate(0,name,OBJ_TREND,0,t1,p1,t2,p2))
     {
      ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
      ObjectSetInteger(0,name,OBJPROP_STYLE,style);
      ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT,false);
      ObjectSetInteger(0,name,OBJPROP_BACK,true);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
      ObjectSetString(0,name,OBJPROP_TOOLTIP,tip);
     }
  }

void Label(const string name,const datetime t,const double p,const string text,const color clr,const ENUM_ANCHOR_POINT anchor)
  {
   if(ObjectCreate(0,name,OBJ_TEXT,0,t,p))
     {
      ObjectSetString(0,name,OBJPROP_TEXT,text);
      ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
      ObjectSetInteger(0,name,OBJPROP_FONTSIZE,8);
      ObjectSetInteger(0,name,OBJPROP_ANCHOR,anchor);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
     }
  }

//--- draw the zones of one engine; `t` are the bar times of the series the engine ran on, `last_t` is the time of the
//--- last bar of the chart, `ex` the extension in seconds
int DrawEngine(CSmcEngine &e,const datetime &t[],const int bars,const string tag,const bool htf,
               const datetime from_t,const datetime right_t,int budget)
  {
   int drawn=0;
   for(int z=e.nz-1; z>=0 && drawn<budget; z--)
     {
      bool live=(e.zones[z].end<0);
      if(!live && !InpShowMitigated)
         continue;
      if(t[e.zones[z].born]<from_t)
         break;                                    // zones are stored in birth order: all older ones are out too
      if(e.zones[z].kind==ZK_OB ? !InpShowOB : !InpShowFVG)
         continue;
      bool bull=(e.zones[z].dir>0);
      color clr=htf ? InpClrHTF : (e.zones[z].kind==ZK_OB ? (bull ? InpClrOBBull : InpClrOBBear) : (bull ? InpClrFVGBull : InpClrFVGBear));
      datetime t2=live ? right_t : t[e.zones[z].end];
      string tip=StringFormat("%s%s %s %s, %s - %s%s",htf ? TfName(InpHTF)+" " : "",bull ? "Bullish" : "Bearish",
                              e.zones[z].kind==ZK_OB ? "order block" : "fair value gap",
                              TimeToString(t[e.zones[z].born]),DoubleToString(e.zones[z].bot,_Digits),
                              DoubleToString(e.zones[z].top,_Digits),live ? "" : " (mitigated)");
      string nm=StringFormat("%s%s%d",PFX,tag,z);
      Rect(nm,t[e.zones[z].t0],e.zones[z].top,t2,e.zones[z].bot,clr,htf ? false : (InpFill && live),tip);
      drawn++;
     }
   return(drawn);
  }

void Redraw(const datetime &time[],const int n,const datetime &htime[],const int hn)
  {
   ObjectsDeleteAll(0,PFX);
   int from_bar=MathMax(0,n-1-InpDrawBars);
   datetime from_t=time[from_bar];
   datetime right_t=time[n-1]+(datetime)((long)InpExtendBars*PeriodSeconds(PERIOD_CURRENT));
   int used=0;
   if(InpHTF!=PERIOD_CURRENT && PeriodSeconds(InpHTF)>PeriodSeconds(PERIOD_CURRENT))
      used+=DrawEngine(g_htf,htime,hn,"H",true,from_t,right_t,InpMaxZones);
   used+=DrawEngine(g_eng,time,n,"Z",false,from_t,right_t,MathMax(0,InpMaxZones-used));
   if(InpShowStruct || InpShowSweeps)
     {
      int shown=0;
      if(InpShowStruct)
         for(int b=g_eng.nb-1; b>=0 && shown<InpMaxZones; b--)
           {
            if(g_eng.breaks[b].at<from_bar)
               break;
            bool up=(g_eng.breaks[b].dir>0);
            color clr=up ? InpClrOBBull : InpClrOBBear;
            string tx=g_eng.breaks[b].choch ? "CHoCH" : "BOS";
            Seg(StringFormat("%sS%d",PFX,b),time[g_eng.breaks[b].frm],g_eng.breaks[b].level,time[g_eng.breaks[b].at],
                g_eng.breaks[b].level,clr,STYLE_DOT,tx);
            Label(StringFormat("%sT%d",PFX,b),time[(g_eng.breaks[b].frm+g_eng.breaks[b].at)/2],g_eng.breaks[b].level,tx,clr,
                  up ? ANCHOR_LOWER : ANCHOR_UPPER);
            shown++;
           }
      shown=0;
      if(InpShowSweeps)
         for(int s=g_eng.ns-1; s>=0 && shown<InpMaxZones; s--)
           {
            if(g_eng.sweeps[s].at<from_bar)
               break;
            bool up=(g_eng.sweeps[s].dir>0);
            Seg(StringFormat("%sW%d",PFX,s),time[g_eng.sweeps[s].frm],g_eng.sweeps[s].level,time[g_eng.sweeps[s].at],
                g_eng.sweeps[s].level,clrSilver,STYLE_DASH,"Liquidity sweep");
            Label(StringFormat("%sX%d",PFX,s),time[g_eng.sweeps[s].at],g_eng.sweeps[s].level,"sweep",clrSilver,
                  up ? ANCHOR_UPPER : ANCHOR_LOWER);
            shown++;
           }
     }
   ChartRedraw();
  }

//--- the alert text for the events of the closed bar `i`
string Events(const double &o[])
  {
   string s="";
   if(InpAlNew)
     {
      if(o[B_OB_BULL_TOP]!=EMPTY_VALUE && InpShowOB)
         s+="new bullish order block "+DoubleToString(o[B_OB_BULL_BOT],_Digits)+"-"+DoubleToString(o[B_OB_BULL_TOP],_Digits)+"; ";
      if(o[B_OB_BEAR_TOP]!=EMPTY_VALUE && InpShowOB)
         s+="new bearish order block "+DoubleToString(o[B_OB_BEAR_BOT],_Digits)+"-"+DoubleToString(o[B_OB_BEAR_TOP],_Digits)+"; ";
      if(o[B_FVG_BULL_TOP]!=EMPTY_VALUE && InpShowFVG)
         s+="new bullish gap "+DoubleToString(o[B_FVG_BULL_BOT],_Digits)+"-"+DoubleToString(o[B_FVG_BULL_TOP],_Digits)+"; ";
      if(o[B_FVG_BEAR_TOP]!=EMPTY_VALUE && InpShowFVG)
         s+="new bearish gap "+DoubleToString(o[B_FVG_BEAR_BOT],_Digits)+"-"+DoubleToString(o[B_FVG_BEAR_TOP],_Digits)+"; ";
     }
   if(InpAlStruct && o[B_STRUCT]!=EMPTY_VALUE)
      s+=StringFormat("%s %s at %s; ",MathAbs(o[B_STRUCT])>1 ? "CHoCH" : "BOS",o[B_STRUCT]>0 ? "up" : "down",
                      DoubleToString(o[B_LEVEL],_Digits));
   if(InpAlSweep && InpShowSweeps)
     {
      if(o[B_SWEEP_BULL]!=EMPTY_VALUE)
         s+="low swept at "+DoubleToString(o[B_SWEEP_BULL],_Digits)+"; ";
      if(o[B_SWEEP_BEAR]!=EMPTY_VALUE)
         s+="high swept at "+DoubleToString(o[B_SWEEP_BEAR],_Digits)+"; ";
     }
   if(InpAlTouch && o[B_TOUCHED]!=EMPTY_VALUE && o[B_TOUCHED]>0)
      s+=StringFormat("%d zone(s) touched; ",(int)o[B_TOUCHED]);
   if(InpAlMit && o[B_MITIGATED]!=EMPTY_VALUE && o[B_MITIGATED]>0)
      s+=StringFormat("%d zone(s) mitigated; ",(int)o[B_MITIGATED]);
   return(s);
  }

//--- the higher-timeframe engine: completed HTF bars only, rebuilt when a new HTF bar has closed
int UpdateHTF(datetime &ht[],bool &changed)
  {
   changed=false;
   if(InpHTF==PERIOD_CURRENT || PeriodSeconds(InpHTF)<=PeriodSeconds(PERIOD_CURRENT))
      return(0);
   datetime cur=iTime(_Symbol,InpHTF,0);
   if(cur==0)
      return(0);
   int want=MathMin(Bars(_Symbol,InpHTF),3000);
   double ho[],hh[],hl[],hc[];
   if(CopyTime(_Symbol,InpHTF,0,want,ht)!=want || CopyOpen(_Symbol,InpHTF,0,want,ho)!=want ||
      CopyHigh(_Symbol,InpHTF,0,want,hh)!=want || CopyLow(_Symbol,InpHTF,0,want,hl)!=want ||
      CopyClose(_Symbol,InpHTF,0,want,hc)!=want)
      return(0);
   if(g_htf_last!=cur || g_htf.done<0)
     {
      g_htf.Reset();
      double ob[];
      ArrayResize(ob,B_COUNT);
      for(int i=0; i<=want-2; i++)
         g_htf.Step(i,ht,ho,hh,hl,hc,ob);
      g_htf_last=cur;
      changed=true;
     }
   return(want);
  }

int OnCalculate(const int rates_total,const int prev_calculated,const datetime &time[],
                const double &open[],const double &high[],const double &low[],const double &close[],
                const long &tick_volume[],const long &volume[],const int &spread[])
  {
   if(rates_total<3)
      return(0);
   if(prev_calculated==0 || g_eng.done>rates_total-2)
      g_eng.Reset();
   bool moved=false;
   for(int i=g_eng.done+1; i<=rates_total-2; i++)
     {
      g_eng.Step(i,time,open,high,low,close,g_out);
      for(int k=0; k<B_COUNT; k++)
         g_buf[k].v[i]=g_out[k];
      moved=true;
      if(i==rates_total-2 && prev_calculated>0)
        {
         string ev=Events(g_out);
         if(ev!="")
            SignalAlert(PRODUCT,ev,time[i],true);
        }
     }
   for(int k=0; k<B_COUNT; k++)
      g_buf[k].v[rates_total-1]=EMPTY_VALUE;
   if(g_no_draw)                                   // non-visual Strategy Tester: no chart, so no objects (the
      return(rates_total);                         // buffers above, read by iCustom and alerts, are unchanged)
   datetime ht[];
   bool hchanged=false;
   int hn=UpdateHTF(ht,hchanged);
   if(moved || hchanged || g_draw_stamp!=rates_total)
     {
      Redraw(time,rates_total,ht,hn);
      g_draw_stamp=rates_total;
     }
   return(rates_total);
  }
//+------------------------------------------------------------------+
