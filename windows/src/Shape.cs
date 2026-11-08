// La forma dell'isola (NotchShape del Mac, Core/Pannelli.swift): spalle concave in alto che si attaccano
// al bordo dello schermo e angoli tondi in basso. Curve quadratiche con gli stessi punti del Mac.
using System;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Animation;

namespace Pulsar
{
    class IslandShape : FrameworkElement
    {
        public static readonly DependencyProperty BottomProperty = DependencyProperty.Register("Bottom", typeof(double), typeof(IslandShape),
            new FrameworkPropertyMetadata(10.0, FrameworkPropertyMetadataOptions.AffectsRender));
        public static readonly DependencyProperty HeadFadeProperty = DependencyProperty.Register("HeadFade", typeof(double), typeof(IslandShape),
            new FrameworkPropertyMetadata(0.0, FrameworkPropertyMetadataOptions.AffectsRender));
        public static readonly DependencyProperty BodyOpacityProperty = DependencyProperty.Register("BodyOpacity", typeof(double), typeof(IslandShape),
            new FrameworkPropertyMetadata(0.0, FrameworkPropertyMetadataOptions.AffectsRender));

        public const double Shoulder = 10;
        public double Bottom { get { return (double)GetValue(BottomProperty); } set { SetValue(BottomProperty, value); } }
        /// <summary>0 = compatta tutta nera; 1 = pannello aperto col fondo Volta.body.</summary>
        public double BodyOpacity { get { return (double)GetValue(BodyOpacityProperty); } set { SetValue(BodyOpacityProperty, value); } }
        public double HeadHeight = 32;

        public IslandShape() { SizeChanged += (s, e) => InvalidateVisual(); IsHitTestVisible = true; }

        public static Geometry Make(double w, double h, double s, double b)
        {
            b = Math.Max(0, Math.Min(b, Math.Min((w - 2 * s) / 2, h - s)));
            var g = new StreamGeometry();
            using (var c = g.Open())
            {
                c.BeginFigure(new Point(0, 0), true, true);
                c.QuadraticBezierTo(new Point(s, 0), new Point(s, s), true, true);
                c.LineTo(new Point(s, h - b), true, true);
                c.QuadraticBezierTo(new Point(s, h), new Point(s + b, h), true, true);
                c.LineTo(new Point(w - s - b, h), true, true);
                c.QuadraticBezierTo(new Point(w - s, h), new Point(w - s, h - b), true, true);
                c.LineTo(new Point(w - s, s), true, true);
                c.QuadraticBezierTo(new Point(w - s, 0), new Point(w, 0), true, true);
            }
            g.Freeze();
            return g;
        }

        protected override void OnRender(DrawingContext dc)
        {
            double w = ActualWidth, h = ActualHeight;
            if (w < 2 * Shoulder + 2 || h < 2) return;
            var geo = Make(w, h, Shoulder, Bottom);
            // ombra disegnata a mano (compatta: nero 9%, 1,5 in basso; aperta: nero 30%, 12 in basso, morbida)
            double k = BodyOpacity, op = 0.09 + 0.21 * k, depth = 1.5 + 10.5 * k, blur = 6 + 14 * k;
            dc.PushTransform(new TranslateTransform(0, depth));
            for (int i = 4; i >= 1; i--)
            {
                var pen = new Pen(new SolidColorBrush(Color.FromArgb((byte)(op / 4 * 255), 0, 0, 0)), blur * i / 4);
                dc.DrawGeometry(null, pen, geo);
            }
            dc.Pop();
            dc.DrawGeometry(T.Ink, null, geo);
            if (BodyOpacity > 0)
            {
                dc.PushOpacity(BodyOpacity);
                dc.DrawGeometry(T.Body, null, geo);
                // la testa sfuma dal nero del notch al grafite: nero 100% a 0, 85% a metà, trasparente in fondo
                var fade = new LinearGradientBrush { StartPoint = new Point(0, 0), EndPoint = new Point(0, 1) };
                fade.GradientStops.Add(new GradientStop(Color.FromArgb(255, 0, 0, 0), 0));
                fade.GradientStops.Add(new GradientStop(Color.FromArgb(217, 0, 0, 0), 0.5));
                fade.GradientStops.Add(new GradientStop(Color.FromArgb(0, 0, 0, 0), 1));
                dc.PushClip(geo);
                dc.DrawRectangle(fade, null, new Rect(0, 0, w, Math.Min(h, HeadHeight + 26)));
                dc.Pop();
                dc.Pop();
            }
        }

        protected override HitTestResult HitTestCore(PointHitTestParameters p)
        {
            var geo = Make(ActualWidth, ActualHeight, Shoulder, Bottom);
            return geo.FillContains(p.HitPoint) ? new PointHitTestResult(this, p.HitPoint) : null;
        }
    }

    /// <summary>cubic-bezier(x1, y1, x2, y2) come nei CSS: la curva del Mac per la misura dell'isola (0.22, 1, 0.36, 1).</summary>
    class CubicEase : EasingFunctionBase
    {
        public double X1 = 0.22, Y1 = 1, X2 = 0.36, Y2 = 1;
        // EaseIn = la curva si applica così com'è (EaseOut, il valore di serie, la ribalterebbe)
        public CubicEase() { EasingMode = EasingMode.EaseIn; }
        protected override double EaseInCore(double t)
        {
            // trova u con Bx(u) = t (Newton, poi bisezione di riserva), restituisce By(u)
            double u = t;
            for (int i = 0; i < 8; i++)
            {
                double x = Bez(u, X1, X2) - t, d = Der(u, X1, X2);
                if (Math.Abs(x) < 1e-5) break;
                if (Math.Abs(d) < 1e-6) break;
                u -= x / d;
            }
            if (u < 0 || u > 1 || Math.Abs(Bez(u, X1, X2) - t) > 1e-3)
            {
                double lo = 0, hi = 1; u = t;
                for (int i = 0; i < 30; i++) { if (Bez(u, X1, X2) < t) lo = u; else hi = u; u = (lo + hi) / 2; }
            }
            return Bez(u, Y1, Y2);
        }
        static double Bez(double u, double a, double b) { double v = 1 - u; return 3 * v * v * u * a + 3 * v * u * u * b + u * u * u; }
        static double Der(double u, double a, double b) { double v = 1 - u; return 3 * v * v * a + 6 * v * u * (b - a) + 3 * u * u * (1 - b); }
        protected override Freezable CreateInstanceCore() { return new CubicEase { X1 = X1, Y1 = Y1, X2 = X2, Y2 = Y2 }; }
    }
}
