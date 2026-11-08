// Musica in riproduzione. Con MEDIA (build.bat prova prima questa strada) legge la sessione
// multimediale di Windows (GlobalSystemMediaTransportControls: Spotify, Chrome, Edge, Musica...).
// Senza, ripiega sul titolo della finestra di Spotify. I comandi passano dai tasti multimediali.
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
#if MEDIA
using Windows.Media.Control;
#endif

namespace Pulsar
{
    class NowPlaying
    {
        public string Title = "";
        public string Artist = "";
        public string App = "";
        public bool Playing;
        public bool Any { get { return Title.Length > 0; } }
    }

    static class Media
    {
        [DllImport("user32.dll")] static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
        const byte VK_NEXT = 0xB0, VK_PREV = 0xB1, VK_PLAY = 0xB3;

        static void Key(byte vk)
        {
            keybd_event(vk, 0, 0, UIntPtr.Zero);
            keybd_event(vk, 0, 2 /*KEYUP*/, UIntPtr.Zero);
        }

        public static void PlayPause() { Key(VK_PLAY); }
        public static void Next() { Key(VK_NEXT); }
        public static void Previous() { Key(VK_PREV); }

        public static string Source
        {
            get
            {
#if MEDIA
                return "Windows media session";
#else
                return "Spotify window title";
#endif
            }
        }

        /// <summary>Da chiamare fuori dal thread dell'interfaccia: può bloccare qualche decimo di secondo.</summary>
        public static NowPlaying Read()
        {
            var np = new NowPlaying();
#if MEDIA
            try
            {
                var mgr = Wait(GlobalSystemMediaTransportControlsSessionManager.RequestAsync());
                var s = mgr == null ? null : mgr.GetCurrentSession();
                if (s != null)
                {
                    var p = Wait(s.TryGetMediaPropertiesAsync());
                    np.Title = p.Title ?? "";
                    np.Artist = p.Artist ?? "";
                    np.App = Pretty(s.SourceAppUserModelId ?? "");
                    np.Playing = s.GetPlaybackInfo().PlaybackStatus == GlobalSystemMediaTransportControlsSessionPlaybackStatus.Playing;
                    return np;
                }
            }
            catch { }
#endif
            try
            {
                foreach (var pr in Process.GetProcessesByName("Spotify"))
                {
                    var t = pr.MainWindowTitle;
                    if (string.IsNullOrEmpty(t)) continue;
                    if (t.StartsWith("Spotify")) { np.Title = "Paused"; np.App = "Spotify"; return np; }
                    int i = t.IndexOf(" - ");
                    if (i > 0) { np.Artist = t.Substring(0, i); np.Title = t.Substring(i + 3); }
                    else np.Title = t;
                    np.App = "Spotify"; np.Playing = true;
                    return np;
                }
            }
            catch { }
            return np;
        }

#if MEDIA
        // Senza System.Runtime.WindowsRuntime (vuole il metadato "Windows" dell'SDK): si aspetta l'operazione a mano.
        static T Wait<T>(Windows.Foundation.IAsyncOperation<T> op)
        {
            var until = DateTime.Now.AddSeconds(3);
            while (op.Status == Windows.Foundation.AsyncStatus.Started && DateTime.Now < until) System.Threading.Thread.Sleep(15);
            return op.Status == Windows.Foundation.AsyncStatus.Completed ? op.GetResults() : default(T);
        }
#endif

        static string Pretty(string aumid)
        {
            var a = aumid.ToLowerInvariant();
            if (a.Contains("spotify")) return "Spotify";
            if (a.Contains("chrome")) return "Chrome";
            if (a.Contains("edge")) return "Edge";
            if (a.Contains("zunemusic") || a.Contains("media")) return "Media Player";
            if (a.Contains("firefox")) return "Firefox";
            int bang = aumid.LastIndexOf('!');
            return bang >= 0 ? aumid.Substring(bang + 1) : aumid.Replace(".exe", "");
        }
    }
}
