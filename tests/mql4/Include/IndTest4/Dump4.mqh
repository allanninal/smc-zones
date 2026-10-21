//+------------------------------------------------------------------+
//|                                                        Dump4.mqh |
//|                                      Copyright 2026, Allan Niñal |
//|                                  https://www.allanninal.dev/mql5 |
//+------------------------------------------------------------------+
//| MT4 test harness for an indicator, run as an EA in the Strategy  |
//| Tester (MT4 iCustom takes its inputs at compile time, so the     |
//| test EA defines IndValue(buf,shift) with its iCustom call        |
//| BEFORE including this file).                                     |
//| During the test: on every new bar, records which signal buffers  |
//| are set on the bar that just closed; on every tick, counts       |
//| signals drawn on the live bar (must stay 0).                     |
//| At the end (tester/files):                                       |
//|   <tag>_<SYM>_<TF>.csv          time,open,high,low,close,b<n>... |
//|                                 for every bar (empty = no value) |
//|   repaint_<tag>_<SYM>_<TF>.csv  closed bars checked, signals     |
//|                                 seen live, mismatches with the   |
//|                                 final values, live-bar signals   |
//+------------------------------------------------------------------+
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0 (see LICENSE)
#property strict

input string InpTag     = "default";       // Tag for the output file names
input string InpBuffers = "0,2,3";   // Buffers to dump
input string InpProbe   = "2,3";     // Signal buffers checked for repainting

int      g_bufs[],g_probe[];
datetime g_bar=0;
datetime g_rec_t[];
int      g_rec_i[];                    // the bar's position counted from the oldest bar (stable as bars are added)
int      g_rec_f[];
int      g_rec_n=0,g_live0=0;

void ParseInts(const string text,int &out[])
  {
   string parts[];
   int n=StringSplit(text,',',parts);
   ArrayResize(out,n);
   for(int k=0; k<n; k++)
      out[k]=(int)StringToInteger(parts[k]);
  }

string TfText()
  {
   switch(_Period)
     {
      case PERIOD_M1:  return("M1");
      case PERIOD_M5:  return("M5");
      case PERIOD_M15: return("M15");
      case PERIOD_M30: return("M30");
      case PERIOD_H1:  return("H1");
      case PERIOD_H4:  return("H4");
      case PERIOD_D1:  return("D1");
     }
   return("M"+IntegerToString(_Period));
  }

//--- bit k set = probe buffer k has a value on the bar at `shift`
int Flags(const int shift)
  {
   int f=0;
   for(int k=0; k<ArraySize(g_probe); k++)
      if(IndValue(g_probe[k],shift)!=EMPTY_VALUE)
         f|=(1<<k);
   return(f);
  }

int OnInit()
  {
   ParseInts(InpBuffers,g_bufs);
   ParseInts(InpProbe,g_probe);
   ArrayResize(g_rec_t,0,100000);
   ArrayResize(g_rec_f,0,100000);
   ArrayResize(g_rec_i,0,100000);
   return(INIT_SUCCEEDED);
  }

void OnTick()
  {
   if(Flags(0)!=0)
      g_live0++;
   if(Time[0]==g_bar)
      return;
   g_bar=Time[0];
   if(Bars<3)
      return;
   ArrayResize(g_rec_t,g_rec_n+1,100000);
   ArrayResize(g_rec_f,g_rec_n+1,100000);
   ArrayResize(g_rec_i,g_rec_n+1,100000);
   g_rec_t[g_rec_n]=Time[1];
   g_rec_i[g_rec_n]=Bars-2;
   g_rec_f[g_rec_n]=Flags(1);
   g_rec_n++;
  }

//--- the dump and the repaint check, once (from OnTester, or OnDeinit outside the tester)
bool g_done=false;
void Finish()
  {
   if(g_done)
      return;
   g_done=true;
   string name=InpTag+"_"+_Symbol+"_"+TfText()+".csv";
   int h=FileOpen(name,FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(h==INVALID_HANDLE)
     {
      Print("Dump4: cannot write ",name," error ",GetLastError());
      return;
     }
   string head="time,open,high,low,close";
   for(int k=0; k<ArraySize(g_bufs); k++)
      head+=",b"+IntegerToString(g_bufs[k]);
   FileWriteString(h,head+"\n");
   for(int s=Bars-1; s>=0; s--)
     {
      string row=TimeToString(Time[s],TIME_DATE|TIME_MINUTES)+","+DoubleToString(Open[s],_Digits)+","+
                 DoubleToString(High[s],_Digits)+","+DoubleToString(Low[s],_Digits)+","+DoubleToString(Close[s],_Digits);
      for(int k=0; k<ArraySize(g_bufs); k++)
        {
         double v=IndValue(g_bufs[k],s);
         row+=","+(v==EMPTY_VALUE ? "" : StringFormat("%.16g",v));
        }
      FileWriteString(h,row+"\n");
     }
   FileClose(h);
   //--- repainting: the signals recorded when each bar closed against the final values
   int bad=0,sig=0,lost=0;
   for(int r=0; r<g_rec_n; r++)
     {
      int s=Bars-1-g_rec_i[r];
      if(s<1 || s>=Bars || Time[s]!=g_rec_t[r])
        {
         lost++;                       // the bar could not be found again: counts as a failure
         continue;
        }
      if(g_rec_f[r]!=0)
         sig++;
      if(Flags(s)!=g_rec_f[r])
         bad++;
     }
   h=FileOpen("repaint_"+name,FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(h!=INVALID_HANDLE)
     {
      FileWriteString(h,StringFormat("closed_bars_checked,%d\nsignals_seen_live,%d\nmismatches,%d\nlive_bar_signals,%d\nbars,%d\nnot_found,%d\n",
                                     g_rec_n-lost,sig,bad,g_live0,Bars,lost));
      FileClose(h);
     }
   PrintFormat("Dump4 %s: %d bars dumped; %d closed bars checked (%d not found), %d signals, %d mismatches, %d live-bar signals",
               name,Bars,g_rec_n-lost,lost,sig,bad,g_live0);
  }

double OnTester()
  {
   Finish();
   return(0.0);
  }

void OnDeinit(const int reason)
  {
   Finish();
  }
//+------------------------------------------------------------------+
