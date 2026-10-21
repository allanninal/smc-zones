//+------------------------------------------------------------------+
//|                                                 SignalAlerts.mqh |
//|                                      Copyright 2026, Allan Niñal |
//|                                  https://www.allanninal.dev/mql5 |
//+------------------------------------------------------------------+
//| MT4 edition of the SMC Zones alert helper: one alert per closed- |
//| bar signal (pop-up, sound, push, e-mail), never during the       |
//| history load, never twice for the same bar, silent in the tester.|
//+------------------------------------------------------------------+
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0 (see LICENSE)
#property strict

input bool   InpAlertPopup = true;          // Pop-up alert
input bool   InpAlertSound = false;         // Play a sound
input string InpSoundFile  = "alert.wav";   // Sound file (terminal Sounds folder)
input bool   InpAlertPush  = false;         // Push notification (set up MetaQuotes ID in Options)
input bool   InpAlertEmail = false;         // E-mail (set up in Options)

datetime g_alert_last=0;                    // bar time of the last alert sent

//--- timeframe as text (M15, H1, ...)
string TfName(const ENUM_TIMEFRAMES tf)
  {
   switch(tf==PERIOD_CURRENT ? _Period : (int)tf)
     {
      case PERIOD_M1:  return("M1");
      case PERIOD_M5:  return("M5");
      case PERIOD_M15: return("M15");
      case PERIOD_M30: return("M30");
      case PERIOD_H1:  return("H1");
      case PERIOD_H4:  return("H4");
      case PERIOD_D1:  return("D1");
      case PERIOD_W1:  return("W1");
      case PERIOD_MN1: return("MN1");
     }
   return("M"+IntegerToString(tf==PERIOD_CURRENT ? _Period : (int)tf));
  }

//--- send one alert for a signal on the closed bar `bar_time`; `live` is false while the history is loading
void SignalAlert(const string product,const string text,const datetime bar_time,const bool live)
  {
   if(!live || bar_time<=g_alert_last || IsTesting())
      return;
   g_alert_last=bar_time;
   string msg=StringFormat("%s %s %s: %s",product,_Symbol,TfName(PERIOD_CURRENT),text);
   if(InpAlertPopup)
      Alert(msg);
   if(InpAlertSound && InpSoundFile!="")
      PlaySound(InpSoundFile);
   if(InpAlertPush && TerminalInfoInteger(TERMINAL_NOTIFICATIONS_ENABLED))
      SendNotification(msg);
   if(InpAlertEmail && TerminalInfoInteger(TERMINAL_EMAIL_ENABLED))
      SendMail(product+" "+_Symbol,msg);
  }
//+------------------------------------------------------------------+
