// Colori e caratteri dell'isola, copiati da Pulsar per Mac (Core/Tema.swift, scale Volta e Night).
// Fase 1: solo Dark Matte. White Matte arriva con i temi (fase 3); i nomi restano gli stessi.
using System.Windows;
using System.Windows.Media;

namespace Pulsar
{
    static class T
    {
        public static Color C(string hex) { return (Color)ColorConverter.ConvertFromString(hex); }
        public static Color A(string hex, double alpha) { var c = C(hex); c.A = (byte)(alpha * 255); return c; }
        public static SolidColorBrush B(Color c) { var b = new SolidColorBrush(c); b.Freeze(); return b; }
        public static SolidColorBrush B(string hex) { return B(C(hex)); }
        public static SolidColorBrush B(string hex, double alpha) { return B(A(hex, alpha)); }

        // Volta (pannello aperto)
        public static readonly SolidColorBrush Body = B("#1D1F29");
        public static readonly SolidColorBrush Card = B("#252836");
        public static readonly SolidColorBrush Card2 = B("#2E3242");
        public static readonly SolidColorBrush T1 = B("#EDEFF6");
        public static readonly SolidColorBrush T2 = B("#EDEFF6", 0.58);
        public static readonly SolidColorBrush T3 = B("#EDEFF6", 0.36);
        public static readonly Color A1 = C("#D6EBFF"), A2 = C("#8FC7FF"), A3 = C("#5C8FCC"), A4 = C("#33507A");
        public static readonly SolidColorBrush A1B = B(A1), A2B = B(A2), A3B = B(A3), A4B = B(A4);
        public static readonly SolidColorBrush Pill = B("#2F3446");
        public static readonly SolidColorBrush PillT = B("#DCE2F0");
        public static readonly SolidColorBrush Prim = B("#CFE6FF");
        public static readonly SolidColorBrush PrimT = B("#13203A");

        // Night (stati di Claude)
        public static readonly SolidColorBrush Red = B("#E07A72");
        public static readonly SolidColorBrush Amber = B("#E3BC79");
        public static readonly SolidColorBrush Ink = B("#000000");

        public static readonly FontFamily UI = new FontFamily("Segoe UI Variable Text, Segoe UI");
        public static readonly FontFamily Icons = new FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets");
        public static readonly FontFamily Mono = new FontFamily("Cascadia Mono, Consolas");

        // Simboli Segoe al posto degli SF Symbols del Mac (scelti a mano, da guardare a schermo)
        public const string GHome = "", GTray = "", GTerm = "", GCode = "";
        public const string GPlay = "", GPause = "", GNext = "", GPrev = "";
        public const string GVol = "", GMute = "", GClose = "", GOpen = "", GStop = "", GGlobe = "";
        public const string GRead = "", GEdit = "", GRun = "", GFind = "", GAgent = "", GPlan = "";
        public const string GWait = "", GDone = "", GThink = "", GTool = "", GMusic = "", GApp = "";
        public const string GChat = "", GFolder = "", GMail = "", GPhoto = "", GCalendar = "", GSettings = "", GBag = "", GVideo = "", GNote = "";
    }
}
