using Gtk;
using Singularity;

namespace SingularityWeatherWidget {

    public class Snapshot : Object {
        private static Snapshot? instance = null;
        private FileMonitor? monitor = null;
        private int64 last_request = 0;
        public Json.Object? root { get; private set; default = null; }

        public signal void changed ();

        public static Snapshot get_default () {
            if (instance == null) instance = new Snapshot ();
            return instance;
        }

        public static string path () {
            return Path.build_filename (Environment.get_user_cache_dir (), "singularity-weather", "snapshot.json");
        }

        private Snapshot () {
            var file = File.new_for_path (path ());
            try {
                DirUtils.create_with_parents (Path.get_dirname (path ()), 0700);
                monitor = file.monitor_file (FileMonitorFlags.NONE, null);
                monitor.changed.connect ((f, other, event) => {
                    if (event == FileMonitorEvent.CHANGES_DONE_HINT || event == FileMonitorEvent.CREATED || event == FileMonitorEvent.DELETED) {
                        load ();
                        changed ();
                    }
                });
            } catch (Error e) {
                warning ("Weather widget: %s", e.message);
            }
            load ();
            Timeout.add_seconds (600, () => {
                refresh_if_stale ();
                return Source.CONTINUE;
            });
        }

        private void load () {
            root = null;
            try {
                string text;
                FileUtils.get_contents (path (), out text);
                var parser = new Json.Parser ();
                parser.load_from_data (text);
                var node = parser.get_root ();
                if (node != null && node.get_node_type () == Json.NodeType.OBJECT) root = node.get_object ();
            } catch (Error e) {
            }
        }

        public Json.Object? place (string id) {
            if (root == null || !root.has_member ("places")) return null;
            string wanted = id != "" ? id : root.get_string_member_with_default ("selected", "");
            Json.Object? first = null;
            foreach (var node in root.get_array_member ("places").get_elements ()) {
                var obj = node.get_object ();
                if (first == null) first = obj;
                if (obj.get_string_member_with_default ("id", "") == wanted) return obj;
            }
            return id != "" ? null : first;
        }

        public Gee.List<Json.Object> places () {
            var list = new Gee.ArrayList<Json.Object> ();
            if (root == null || !root.has_member ("places")) return list;
            foreach (var node in root.get_array_member ("places").get_elements ()) list.add (node.get_object ());
            return list;
        }

        public string unit () {
            return root != null ? root.get_string_member_with_default ("units", "") : "";
        }

        public void refresh_if_stale () {
            int64 now = get_real_time () / 1000000;
            bool stale = root == null;
            foreach (var p in places ()) {
                if (now - p.get_int_member_with_default ("fetched_at", 0) > 1800) stale = true;
            }
            if (root != null && places ().size == 0) stale = false;
            if (!stale || now - last_request < 900) return;
            last_request = now;
            call_app ("refresh-snapshot", null);
        }

        public static void call_app (string action, Variant? parameter) {
            var parameters = new VariantBuilder (new VariantType ("av"));
            if (parameter != null) parameters.add ("v", parameter);
            var platform = new VariantBuilder (new VariantType ("a{sv}"));
            Bus.get.begin (BusType.SESSION, null, (o, r) => {
                try {
                    var bus = Bus.get.end (r);
                    bus.call.begin ("dev.sinty.weather", "/dev/sinty/weather", "org.freedesktop.Application", "ActivateAction",
                        new Variant ("(s@av@a{sv})", action, parameters.end (), platform.end ()),
                        null, DBusCallFlags.NONE, 30000, null, (obj, res) => {
                            try {
                                bus.call.end (res);
                            } catch (Error e) {
                                warning ("Weather widget: %s", e.message);
                            }
                        });
                } catch (Error e) {
                    warning ("Weather widget: %s", e.message);
                }
            });
        }
    }

    public class ForecastProvider : Object, OverviewWidgetProvider {
        public string id { get { return "weather.forecast"; } }
        public string provider_id { get { return "dev.sinty.weather"; } }
        public string display_name { get { return _("Weather"); } }
        public string icon_name { get { return "weather-few-clouds-symbolic"; } }
        public WidgetSize[] supported_sizes {
            get {
                if (_sizes == null) {
                    _sizes = new WidgetSize[3];
                    _sizes[0] = WidgetSize (1, 1);
                    _sizes[1] = WidgetSize (2, 1);
                    _sizes[2] = WidgetSize (4, 2);
                }
                return _sizes;
            }
        }
        private WidgetSize[] _sizes;

        public Gtk.Widget create_instance (string instance_id, WidgetSize size, Variant? config) {
            string place = config != null && config.is_of_type (VariantType.STRING) ? config.get_string () : "";
            return new ForecastInstance (size, place);
        }

        public bool can_configure (string instance_id) {
            return Snapshot.get_default ().places ().size > 1;
        }

        public void configure_instance (string instance_id) {
            var registry = OverviewWidgetRegistry.get_default ();
            Variant? current = registry.get_instance_config (instance_id);
            string place = current != null && current.is_of_type (VariantType.STRING) ? current.get_string () : "";

            var dialog = new Singularity.Shell.ShellDialog (GLib.Application.get_default ());
            dialog.set_default_size (380, -1);
            var box = new Box (Orientation.VERTICAL, 16);
            box.margin_top = 24;
            box.margin_bottom = 24;
            box.margin_start = 24;
            box.margin_end = 24;

            var options = new Gee.ArrayList<Singularity.Core.AppSettingOption> ();
            var follow = new Singularity.Core.AppSettingOption ();
            follow.id = "";
            follow.label = _("Same as Weather");
            options.add (follow);
            foreach (var p in Snapshot.get_default ().places ()) {
                var opt = new Singularity.Core.AppSettingOption ();
                opt.id = p.get_string_member_with_default ("id", "");
                opt.label = p.get_string_member_with_default ("name", "");
                options.add (opt);
            }
            var group = new Singularity.Widgets.PreferencesGroup ();
            group.title = _("Weather");
            var row = new Singularity.Widgets.SelectionRow.with_options (_("Place"), options, place);
            string chosen = place;
            row.selected.connect ((item) => chosen = item);
            group.add_row (row);
            box.append (group);

            var buttons = new Box (Orientation.HORIZONTAL, 8);
            buttons.halign = Align.END;
            var cancel = new Button.with_label (_("Cancel"));
            cancel.clicked.connect (() => dialog.close_dialog ());
            buttons.append (cancel);
            var save = new Button.with_label (_("Save"));
            save.add_css_class ("suggested-action");
            save.clicked.connect (() => {
                registry.save_instance_config (instance_id, chosen != "" ? new Variant.string (chosen) : null);
                dialog.close_dialog ();
            });
            buttons.append (save);
            box.append (buttons);
            dialog.content_box.append (box);
            dialog.present ();
        }
    }

    public class ForecastInstance : Box {
        private WidgetSize size;
        private string place_id;
        private Box content;
        private ulong handler;

        public ForecastInstance (WidgetSize size, string place_id) {
            Object (orientation: Orientation.VERTICAL, spacing: 0);
            this.size = size;
            this.place_id = place_id;
            add_css_class ("overview-widget-card");
            add_css_class ("overview-weather");
            hexpand = true;
            vexpand = true;
            overflow = Overflow.HIDDEN;
            content = new Box (Orientation.VERTICAL, 0);
            content.hexpand = true;
            content.vexpand = true;
            append (content);

            var click = new GestureClick ();
            click.released.connect (() => open ());
            add_controller (click);
            cursor = new Gdk.Cursor.from_name ("pointer", null);

            var snapshot = Snapshot.get_default ();
            handler = snapshot.changed.connect (rebuild);
            destroy.connect (() => {
                if (handler != 0) snapshot.disconnect (handler);
                handler = 0;
            });
            rebuild ();
            snapshot.refresh_if_stale ();
        }

        private void open () {
            var p = Snapshot.get_default ().place (place_id);
            if (p == null) {
                Snapshot.call_app ("add-place", null);
                close_overview_later ();
                return;
            }
            Snapshot.call_app ("show-place", new Variant.string (p.get_string_member_with_default ("id", "")));
            close_overview_later ();
        }

        private void close_overview_later () {
            Timeout.add (600, () => {
                if (get_mapped ()) Singularity.OverviewWidgetRegistry.get_default ().close_overview ();
                return Source.REMOVE;
            });
        }

        private void clear () {
            Widget? child;
            while ((child = content.get_first_child ()) != null) content.remove (child);
        }

        private static Label label (string text, string? css = null) {
            var l = new Label (text);
            l.ellipsize = Pango.EllipsizeMode.END;
            if (css != null) l.add_css_class (css);
            return l;
        }

        private static Image icon (string name, int px) {
            var img = new Image.from_icon_name (name);
            img.pixel_size = px;
            return img;
        }

        private void rebuild () {
            clear ();
            var snapshot = Snapshot.get_default ();
            var p = snapshot.place (place_id);
            if (p == null || !p.has_member ("temperature")) {
                var box = new Box (Orientation.VERTICAL, 6);
                box.valign = Align.CENTER;
                box.vexpand = true;
                box.margin_start = 12;
                box.margin_end = 12;
                box.append (icon ("dev.sinty.weather", size.w > 1 ? 48 : 40));
                string text = p == null ? _("Add a place in Weather") : _("Loading forecast");
                var l = label (text, "caption");
                l.wrap = true;
                l.justify = Justification.CENTER;
                l.ellipsize = Pango.EllipsizeMode.NONE;
                box.append (l);
                content.append (box);
                tooltip_text = p != null ? p.get_string_member_with_default ("name", "") : null;
                return;
            }
            string name = p.get_string_member_with_default ("name", "");
            string condition = p.get_string_member_with_default ("condition", "");
            tooltip_text = "%s, %s %s".printf (name, p.get_string_member_with_default ("temperature", ""), condition);
            if (size.w == 1) build_small (p);
            else if (size.h == 1) build_wide (p);
            else build_large (p);
        }

        private string high_low (Json.Object p) {
            if (!p.has_member ("high")) return "";
            return _("H %s  L %s").printf (p.get_string_member ("high"), p.get_string_member ("low"));
        }

        private void build_small (Json.Object p) {
            var box = new Box (Orientation.VERTICAL, 2);
            box.valign = Align.CENTER;
            box.vexpand = true;
            box.margin_start = 8;
            box.margin_end = 8;
            box.append (icon (p.get_string_member_with_default ("icon", "weather-few-clouds"), 44));
            box.append (label (p.get_string_member_with_default ("temperature", ""), "title-2"));
            var place = label (p.get_string_member_with_default ("name", ""), "caption");
            place.add_css_class ("dim-label");
            box.append (place);
            content.append (box);
        }

        private Box current_row (Json.Object p, int icon_px) {
            var row = new Box (Orientation.HORIZONTAL, 12);
            row.append (icon (p.get_string_member_with_default ("icon", "weather-few-clouds"), icon_px));
            var texts = new Box (Orientation.VERTICAL, 0);
            texts.valign = Align.CENTER;
            texts.hexpand = true;
            var place = label (p.get_string_member_with_default ("name", ""), "caption-heading");
            place.xalign = 0;
            place.add_css_class ("dim-label");
            texts.append (place);
            var temp = label (p.get_string_member_with_default ("temperature", ""), "title-1");
            temp.xalign = 0;
            texts.append (temp);
            var cond = label (p.get_string_member_with_default ("condition", ""));
            cond.xalign = 0;
            texts.append (cond);
            string hl = high_low (p);
            if (hl != "") {
                var h = label (hl, "caption");
                h.xalign = 0;
                h.add_css_class ("dim-label");
                texts.append (h);
            }
            row.append (texts);
            return row;
        }

        private void build_wide (Json.Object p) {
            var row = current_row (p, 64);
            row.valign = Align.CENTER;
            row.vexpand = true;
            row.margin_start = 14;
            row.margin_end = 14;
            content.append (row);
        }

        private void build_large (Json.Object p) {
            var box = new Box (Orientation.VERTICAL, 10);
            box.margin_top = 12;
            box.margin_bottom = 12;
            box.margin_start = 16;
            box.margin_end = 16;
            box.vexpand = true;
            box.append (current_row (p, 64));

            int64 now = get_real_time () / 1000000;
            var hours = new Box (Orientation.HORIZONTAL, 0);
            hours.homogeneous = true;
            hours.vexpand = true;
            int count = 0;
            if (p.has_member ("hours")) {
                foreach (var node in p.get_array_member ("hours").get_elements ()) {
                    var h = node.get_object ();
                    if (h.get_int_member_with_default ("t", 0) + 3600 <= now) continue;
                    var cell = new Box (Orientation.VERTICAL, 2);
                    cell.valign = Align.CENTER;
                    var t = label (count == 0 ? _("Now") : h.get_string_member_with_default ("label", ""), "caption");
                    t.add_css_class ("dim-label");
                    cell.append (t);
                    cell.append (icon (h.get_string_member_with_default ("icon", ""), 32));
                    cell.append (label (h.get_string_member_with_default ("temperature", "")));
                    hours.append (cell);
                    if (++count == 8) break;
                }
            }
            if (count > 0) box.append (hours);

            var days = new Box (Orientation.HORIZONTAL, 0);
            days.homogeneous = true;
            days.vexpand = true;
            int dcount = 0;
            var today = new DateTime.now_local ();
            int64 start_of_today = new DateTime.local (today.get_year (), today.get_month (), today.get_day_of_month (), 0, 0, 0).to_unix ();
            if (p.has_member ("days")) {
                foreach (var node in p.get_array_member ("days").get_elements ()) {
                    var d = node.get_object ();
                    if (d.get_int_member_with_default ("t", 0) < start_of_today - 43200) continue;
                    var cell = new Box (Orientation.VERTICAL, 2);
                    cell.valign = Align.CENTER;
                    var t = label (dcount == 0 ? _("Today") : d.get_string_member_with_default ("label", ""), "caption-heading");
                    cell.append (t);
                    cell.append (icon (d.get_string_member_with_default ("icon", ""), 32));
                    var hl = label ("%s  %s".printf (d.get_string_member_with_default ("high", ""), d.get_string_member_with_default ("low", "")), "caption");
                    cell.append (hl);
                    days.append (cell);
                    if (++dcount == 5) break;
                }
            }
            if (dcount > 0) {
                box.append (new Separator (Orientation.HORIZONTAL));
                box.append (days);
            }
            content.append (box);
        }
    }

    [CCode (cname = "singularity_weather_widget_new")]
    public static Object singularity_weather_widget_new () {
        string locale_dir = "/usr/share/locale";
        try {
            string exe = FileUtils.read_link ("/proc/self/exe");
            locale_dir = Path.build_filename (Path.get_dirname (Path.get_dirname (exe)), "share", "locale");
        } catch (Error e) {
        }
        Intl.bindtextdomain ("singularity-weather", locale_dir);
        Intl.bind_textdomain_codeset ("singularity-weather", "UTF-8");
        return new ForecastProvider ();
    }
}
