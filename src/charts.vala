using Gtk;

namespace Singularity.Apps.Weather {

    internal static void set_rgb (Cairo.Context cr, string hex, double alpha = 1) {
        var c = Gdk.RGBA ();
        c.parse (hex);
        cr.set_source_rgba (c.red, c.green, c.blue, alpha);
    }

    internal static void draw_icon (Gtk.Snapshot snapshot, Widget widget, string name, double x, double y, int size) {
        var theme = IconTheme.get_for_display (widget.get_display ());
        var paintable = theme.lookup_icon (name, null, size, widget.get_scale_factor (), widget.get_direction (), 0);
        snapshot.save ();
        var point = Graphene.Point ();
        point.init ((float) x, (float) y);
        snapshot.translate (point);
        paintable.snapshot (snapshot, size, size);
        snapshot.restore ();
    }

    public class HourlyStrip : Widget {
        public const int COLUMN = 60;
        private const int HEIGHT = 178;
        private Gee.List<Hour?> hours = new Gee.ArrayList<Hour?> ();
        private string warm = "#f5a623";
        private string rain = "#3b82f6";

        public HourlyStrip () {
            add_css_class ("weather-hourly");
        }

        public void set_hours (Gee.List<Hour?> list) {
            hours = list;
            queue_resize ();
            queue_draw ();
        }

        public override void measure (Orientation orientation, int for_size, out int minimum, out int natural, out int minimum_baseline, out int natural_baseline) {
            minimum_baseline = natural_baseline = -1;
            if (orientation == Orientation.HORIZONTAL) {
                minimum = natural = int.max (1, hours.size) * COLUMN;
            } else {
                minimum = natural = HEIGHT;
            }
        }

        public override void snapshot (Gtk.Snapshot snapshot) {
            if (hours.size == 0) return;
            var fg = get_color ();
            int width = get_width ();
            var cr = snapshot.append_cairo ({ { 0, 0 }, { width, HEIGHT } });
            double lo = double.MAX, hi = -double.MAX;
            foreach (var h in hours) {
                lo = double.min (lo, h.temperature);
                hi = double.max (hi, h.temperature);
            }
            if (hi - lo < 4) {
                double mid = (hi + lo) / 2;
                lo = mid - 2;
                hi = mid + 2;
            }
            double top = 82, bottom = 118;
            double[] ys = new double[hours.size];
            for (int i = 0; i < hours.size; i++) {
                ys[i] = bottom - (hours[i].temperature - lo) / (hi - lo) * (bottom - top);
            }
            cr.set_line_width (2);
            cr.set_line_join (Cairo.LineJoin.ROUND);
            cr.set_line_cap (Cairo.LineCap.ROUND);
            set_rgb (cr, warm);
            for (int i = 0; i < hours.size; i++) {
                double x = i * COLUMN + COLUMN / 2.0;
                if (i == 0) cr.move_to (x, ys[i]);
                else {
                    double px = (i - 1) * COLUMN + COLUMN / 2.0;
                    cr.curve_to (px + COLUMN / 2.0, ys[i - 1], x - COLUMN / 2.0, ys[i], x, ys[i]);
                }
            }
            cr.stroke ();
            for (int i = 0; i < hours.size; i++) {
                double x = i * COLUMN + COLUMN / 2.0;
                cr.arc (x, ys[i], 3.2, 0, 2 * Math.PI);
                set_rgb (cr, warm);
                cr.fill ();
            }
            for (int i = 0; i < hours.size; i++) {
                var h = hours[i];
                double x = i * COLUMN;
                int p = h.precipitation_probability;
                double bar_h = 18 * p / 100.0;
                if (p > 0) {
                    set_rgb (cr, rain, p >= 30 ? 0.85 : 0.4);
                    double bx = x + COLUMN / 2.0 - 9, by = HEIGHT - 20 - bar_h;
                    double r = double.min (3, bar_h / 2);
                    cr.new_sub_path ();
                    cr.arc (bx + r, by + r, r, Math.PI, 1.5 * Math.PI);
                    cr.arc (bx + 18 - r, by + r, r, 1.5 * Math.PI, 2 * Math.PI);
                    cr.line_to (bx + 18, HEIGHT - 20);
                    cr.line_to (bx, HEIGHT - 20);
                    cr.close_path ();
                    cr.fill ();
                }
            }
            cr.set_source_rgba (fg.red, fg.green, fg.blue, 0.12);
            cr.set_line_width (1);
            cr.move_to (0, HEIGHT - 19.5);
            cr.line_to (width, HEIGHT - 19.5);
            cr.stroke ();

            var layout = create_pango_layout ("");
            for (int i = 0; i < hours.size; i++) {
                var h = hours[i];
                double cx = i * COLUMN + COLUMN / 2.0;
                bool now = i == 0;
                layout.set_markup (now ? "<b>%s</b>".printf (_("Now")) : "<small>%s</small>".printf (h.time.format ("%H")), -1);
                int lw, lh;
                layout.get_pixel_size (out lw, out lh);
                cr.move_to (cx - lw / 2.0, 2);
                cr.set_source_rgba (fg.red, fg.green, fg.blue, now ? 1 : 0.65);
                Pango.cairo_show_layout (cr, layout);

                layout.set_markup ("<b>%s</b>".printf (Format.temperature (h.temperature)), -1);
                layout.get_pixel_size (out lw, out lh);
                cr.move_to (cx - lw / 2.0 + 2, ys[i] - lh - 5);
                cr.set_source_rgba (fg.red, fg.green, fg.blue, 1);
                Pango.cairo_show_layout (cr, layout);

                if (h.precipitation_probability >= 20) {
                    layout.set_markup ("<small>%d%%</small>".printf (h.precipitation_probability), -1);
                    layout.get_pixel_size (out lw, out lh);
                    cr.move_to (cx - lw / 2.0, HEIGHT - lh);
                    cr.set_source_rgba (fg.red, fg.green, fg.blue, 0.7);
                    Pango.cairo_show_layout (cr, layout);
                }
            }
            for (int i = 0; i < hours.size; i++) {
                var cond = Conditions.describe (hours[i].code, hours[i].day);
                draw_icon (snapshot, this, cond.icon, i * COLUMN + COLUMN / 2.0 - 11, 26, 22);
            }
        }
    }

    public class RangeBar : DrawingArea {
        private double lo;
        private double hi;
        private double day_lo;
        private double day_hi;
        private double current = double.NAN;
        private bool imperial;

        public RangeBar (double lo, double hi, double day_lo, double day_hi, double current, bool imperial) {
            this.lo = lo;
            this.hi = hi;
            this.day_lo = day_lo;
            this.day_hi = day_hi;
            this.current = current;
            this.imperial = imperial;
            set_size_request (120, 12);
            hexpand = true;
            valign = Align.CENTER;
            set_draw_func (draw);
        }

        private string color_for (double t) {
            double c = imperial ? (t - 32) * 5 / 9 : t;
            if (c < 0) return "#7dd3fc";
            if (c < 10) return "#38bdf8";
            if (c < 18) return "#34d399";
            if (c < 25) return "#facc15";
            if (c < 32) return "#fb923c";
            return "#ef4444";
        }

        private void draw (DrawingArea area, Cairo.Context cr, int width, int height) {
            var fg = get_color ();
            double h = 6, y = (height - h) / 2;
            double span = double.max (1, hi - lo);
            cr.set_source_rgba (fg.red, fg.green, fg.blue, 0.12);
            rounded (cr, 0, y, width, h);
            cr.fill ();
            double x1 = (day_lo - lo) / span * width;
            double x2 = (day_hi - lo) / span * width;
            if (x2 - x1 < h) x2 = x1 + h;
            var grad = new Cairo.Pattern.linear (x1, 0, x2, 0);
            var a = Gdk.RGBA ();
            a.parse (color_for (day_lo));
            var b = Gdk.RGBA ();
            b.parse (color_for (day_hi));
            grad.add_color_stop_rgb (0, a.red, a.green, a.blue);
            grad.add_color_stop_rgb (1, b.red, b.green, b.blue);
            cr.set_source (grad);
            rounded (cr, x1, y, x2 - x1, h);
            cr.fill ();
            if (!current.is_nan ()) {
                double cx = ((current - lo) / span * width).clamp (h / 2, width - h / 2);
                cr.arc (cx, height / 2.0, 4.5, 0, 2 * Math.PI);
                cr.set_source_rgba (1, 1, 1, 1);
                cr.fill_preserve ();
                cr.set_source_rgba (0, 0, 0, 0.35);
                cr.set_line_width (1.2);
                cr.stroke ();
            }
        }

        private static void rounded (Cairo.Context cr, double x, double y, double w, double h) {
            double r = h / 2;
            cr.new_sub_path ();
            cr.arc (x + r, y + r, r, Math.PI / 2, 3 * Math.PI / 2);
            cr.arc (x + w - r, y + r, r, 3 * Math.PI / 2, Math.PI / 2);
            cr.close_path ();
        }
    }

    public class SunArc : DrawingArea {
        private double progress = -1;

        public SunArc () {
            set_size_request (-1, 78);
            hexpand = true;
            set_draw_func (draw);
        }

        public void set_progress (double value) {
            progress = value;
            queue_draw ();
        }

        private void draw (DrawingArea area, Cairo.Context cr, int width, int height) {
            var fg = get_color ();
            double cx = width / 2.0;
            double rx = width / 2.0 - 8;
            double ry = height - 14;
            double base_y = height - 6;
            cr.set_line_width (1);
            cr.set_source_rgba (fg.red, fg.green, fg.blue, 0.25);
            cr.move_to (0, base_y + 0.5);
            cr.line_to (width, base_y + 0.5);
            cr.stroke ();
            half_ellipse (cr, cx, base_y, rx, ry, Math.PI, 2 * Math.PI);
            cr.set_line_width (2);
            cr.set_dash ({ 3, 4 }, 0);
            cr.set_source_rgba (fg.red, fg.green, fg.blue, 0.3);
            cr.stroke ();
            cr.set_dash (null, 0);
            if (progress < 0 || progress > 1) {
                double sx = progress > 1 ? cx + rx : cx - rx;
                cr.arc (sx, base_y, 5, 0, 2 * Math.PI);
                cr.set_source_rgba (fg.red, fg.green, fg.blue, 0.4);
                cr.fill ();
                return;
            }
            double angle = Math.PI + progress * Math.PI;
            half_ellipse (cr, cx, base_y, rx, ry, Math.PI, angle);
            set_rgb (cr, "#f5a623");
            cr.set_line_width (3);
            cr.stroke ();
            double sx = cx + rx * Math.cos (angle);
            double sy = base_y + ry * Math.sin (angle);
            var glow = new Cairo.Pattern.radial (sx, sy, 0, sx, sy, 16);
            glow.add_color_stop_rgba (0, 0.98, 0.75, 0.2, 0.55);
            glow.add_color_stop_rgba (1, 0.98, 0.75, 0.2, 0);
            cr.set_source (glow);
            cr.arc (sx, sy, 16, 0, 2 * Math.PI);
            cr.fill ();
            set_rgb (cr, "#fbbf24");
            cr.arc (sx, sy, 6, 0, 2 * Math.PI);
            cr.fill ();
        }

        private static void half_ellipse (Cairo.Context cr, double cx, double cy, double rx, double ry, double from, double to) {
            cr.new_path ();
            int steps = 64;
            for (int i = 0; i <= steps; i++) {
                double a = from + (to - from) * i / steps;
                double x = cx + rx * Math.cos (a), y = cy + ry * Math.sin (a);
                if (i == 0) cr.move_to (x, y); else cr.line_to (x, y);
            }
        }
    }

    public class Compass : DrawingArea {
        private double direction = 0;

        public Compass () {
            set_size_request (64, 64);
            halign = Align.CENTER;
            set_draw_func (draw);
        }

        public void set_direction (double degrees) {
            direction = degrees;
            queue_draw ();
        }

        private void draw (DrawingArea area, Cairo.Context cr, int width, int height) {
            var fg = get_color ();
            double cx = width / 2.0, cy = height / 2.0, r = double.min (width, height) / 2.0 - 3;
            cr.set_line_width (1.5);
            cr.set_source_rgba (fg.red, fg.green, fg.blue, 0.25);
            cr.arc (cx, cy, r, 0, 2 * Math.PI);
            cr.stroke ();
            for (int i = 0; i < 4; i++) {
                double a = i * Math.PI / 2 - Math.PI / 2;
                cr.move_to (cx + (r - 5) * Math.cos (a), cy + (r - 5) * Math.sin (a));
                cr.line_to (cx + r * Math.cos (a), cy + r * Math.sin (a));
            }
            cr.stroke ();
            double to = (direction + 180) * Math.PI / 180 - Math.PI / 2;
            double tx = cx + (r - 6) * Math.cos (to), ty = cy + (r - 6) * Math.sin (to);
            double fx = cx - (r - 10) * Math.cos (to), fy = cy - (r - 10) * Math.sin (to);
            set_rgb (cr, "#3b82f6");
            cr.set_line_width (3);
            cr.set_line_cap (Cairo.LineCap.ROUND);
            cr.move_to (fx, fy);
            cr.line_to (tx, ty);
            cr.stroke ();
            double side = 0.5;
            cr.move_to (tx, ty);
            cr.line_to (tx - 9 * Math.cos (to - side), ty - 9 * Math.sin (to - side));
            cr.line_to (tx - 9 * Math.cos (to + side), ty - 9 * Math.sin (to + side));
            cr.close_path ();
            cr.fill ();
        }
    }
}
