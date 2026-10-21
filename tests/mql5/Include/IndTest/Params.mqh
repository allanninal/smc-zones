//+------------------------------------------------------------------+
//|                                                       Params.mqh |
//|                                      Copyright 2026, Allan Niñal |
//+------------------------------------------------------------------+
//| Build an indicator handle from a path and a parameter string     |
//| "d:1.5|i:10|b:false|s:alert.wav" (d double, i int/enum, b bool, |
//| s string, c color), so test tools can drive any indicator.       |
//+------------------------------------------------------------------+
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0 (see LICENSE)
int MakeHandle(const string sym,const ENUM_TIMEFRAMES tf,const string path,const string spec)
  {
   string parts[];
   int n=(spec=="" ? 0 : StringSplit(spec,'|',parts));
   MqlParam p[];
   ArrayResize(p,n+1);
   p[0].type=TYPE_STRING;
   p[0].string_value=path;
   for(int i=0; i<n; i++)
     {
      int colon=StringFind(parts[i],":");              // "s:" (an empty string input) is valid: split on the first colon
      if(colon<1)
         return(INVALID_HANDLE);
      string t=StringSubstr(parts[i],0,colon);
      string v=StringSubstr(parts[i],colon+1);
      if(t=="d")      { p[i+1].type=TYPE_DOUBLE; p[i+1].double_value=StringToDouble(v); }
      else if(t=="i") { p[i+1].type=TYPE_INT;    p[i+1].integer_value=StringToInteger(v); }
      else if(t=="b") { p[i+1].type=TYPE_BOOL;   p[i+1].integer_value=(v=="true" || v=="1"); }
      else                { p[i+1].type=TYPE_STRING; p[i+1].string_value=v; }
     }
   return(IndicatorCreate(sym,tf,IND_CUSTOM,n+1,p));
  }

ENUM_TIMEFRAMES TfFromName(const string s)
  {
   string n[]={"M1","M5","M15","M30","H1","H4","D1","W1"};
   ENUM_TIMEFRAMES t[]={PERIOD_M1,PERIOD_M5,PERIOD_M15,PERIOD_M30,PERIOD_H1,PERIOD_H4,PERIOD_D1,PERIOD_W1};
   for(int i=0; i<ArraySize(n); i++)
      if(n[i]==s)
         return(t[i]);
   return(PERIOD_CURRENT);
  }

int ParseInts(const string s,int &out[])
  {
   string parts[];
   int n=StringSplit(s,',',parts);
   ArrayResize(out,n);
   for(int i=0; i<n; i++)
      out[i]=(int)StringToInteger(parts[i]);
   return(n);
  }
