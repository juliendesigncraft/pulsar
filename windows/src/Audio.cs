// Volume di sistema con Core Audio (IAudioEndpointVolume). Nessuna libreria esterna.
// Scritto in C# 5: compila col csc.exe che Windows ha già (.NET Framework 4.8).
using System;
using System.Runtime.InteropServices;

namespace Pulsar
{
    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
    class MMDeviceEnumeratorCom { }

    [Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDeviceEnumerator
    {
        int NotImpl1();
        [PreserveSig] int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice ppDevice);
    }

    [Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDevice
    {
        [PreserveSig] int Activate(ref Guid iid, int dwClsCtx, IntPtr pActivationParams, [MarshalAs(UnmanagedType.IUnknown)] out object ppInterface);
    }

    [Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioEndpointVolume
    {
        int RegisterControlChangeNotify(IntPtr pNotify);
        int UnregisterControlChangeNotify(IntPtr pNotify);
        int GetChannelCount(out int pnChannelCount);
        int SetMasterVolumeLevel(float fLevelDB, ref Guid pguidEventContext);
        int SetMasterVolumeLevelScalar(float fLevel, ref Guid pguidEventContext);
        int GetMasterVolumeLevel(out float pfLevelDB);
        int GetMasterVolumeLevelScalar(out float pfLevel);
        int SetChannelVolumeLevel(uint nChannel, float fLevelDB, ref Guid pguidEventContext);
        int SetChannelVolumeLevelScalar(uint nChannel, float fLevel, ref Guid pguidEventContext);
        int GetChannelVolumeLevel(uint nChannel, out float pfLevelDB);
        int GetChannelVolumeLevelScalar(uint nChannel, out float pfLevel);
        int SetMute([MarshalAs(UnmanagedType.Bool)] bool bMute, ref Guid pguidEventContext);
        int GetMute(out bool pbMute);
    }

    static class Audio
    {
        static IAudioEndpointVolume Endpoint()
        {
            try
            {
                var en = (IMMDeviceEnumerator)new MMDeviceEnumeratorCom();
                IMMDevice dev;
                if (en.GetDefaultAudioEndpoint(0 /*eRender*/, 1 /*eMultimedia*/, out dev) != 0 || dev == null) return null;
                var iid = typeof(IAudioEndpointVolume).GUID;
                object o;
                if (dev.Activate(ref iid, 23 /*CLSCTX_ALL*/, IntPtr.Zero, out o) != 0) return null;
                return o as IAudioEndpointVolume;
            }
            catch { return null; }
        }

        /// <summary>Volume 0..1, oppure -1 se non c'è un'uscita audio.</summary>
        public static float Get()
        {
            var ep = Endpoint();
            if (ep == null) return -1f;
            float v; ep.GetMasterVolumeLevelScalar(out v);
            return v;
        }

        public static void Set(float v)
        {
            var ep = Endpoint();
            if (ep == null) return;
            if (v < 0) v = 0; if (v > 1) v = 1;
            var g = Guid.Empty;
            ep.SetMasterVolumeLevelScalar(v, ref g);
            if (v > 0) ep.SetMute(false, ref g);
        }

        public static bool Muted()
        {
            var ep = Endpoint();
            if (ep == null) return false;
            bool m; ep.GetMute(out m);
            return m;
        }

        public static void ToggleMute()
        {
            var ep = Endpoint();
            if (ep == null) return;
            bool m; ep.GetMute(out m);
            var g = Guid.Empty;
            ep.SetMute(!m, ref g);
        }
    }
}
