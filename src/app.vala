using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Weather {

    public class WeatherApp : Singularity.Application {
        public GLib.Settings settings { get; private set; }
        public WeatherService service { get; private set; }
        private WeatherSearch search;
        private string pending_action = "";
        private bool refreshing = false;

        public WeatherApp () {
            Object (application_id: "dev.sinty.weather", flags: ApplicationFlags.DEFAULT_FLAGS);
            add_main_option ("add-place", 0, OptionFlags.NONE, OptionArg.NONE, _("Search for a place to add"), null);
            add_main_option ("use-location", 0, OptionFlags.NONE, OptionArg.NONE, _("Add the weather where you are now"), null);
            search = new WeatherSearch (this);
            search.export (this);
        }

        protected override int handle_local_options (VariantDict options) {
            string action = options.contains ("add-place") ? "add-place" : (options.contains ("use-location") ? "use-location" : "");
            if (action == "") return -1;
            try {
                register (null);
            } catch (Error e) {
                warning ("Weather: %s", e.message);
                return 1;
            }
            if (get_is_remote ()) {
                activate_action (action, null);
                return 0;
            }
            pending_action = action;
            return -1;
        }

        private uint forecast_bus_id = 0;

        public override bool dbus_register (DBusConnection connection, string object_path) throws Error {
            if (!base.dbus_register (connection, object_path)) return false;
            forecast_bus_id = connection.register_object ("/dev/sinty/weather/Forecast", new ForecastBus (this));
            return true;
        }

        public override void dbus_unregister (DBusConnection connection, string object_path) {
            if (forecast_bus_id != 0) connection.unregister_object (forecast_bus_id);
            forecast_bus_id = 0;
            base.dbus_unregister (connection, object_path);
        }

        protected override void startup () {
            base.startup ();
            settings = new GLib.Settings ("dev.sinty.weather");
            service = new WeatherService ();
            var provider = new CssProvider ();
            provider.load_from_string (CSS);
            StyleContext.add_provider_for_display (Gdk.Display.get_default (), provider, STYLE_PROVIDER_PRIORITY_USER + 1);

            var menu = new GLib.Menu ();
            var file_menu = new GLib.Menu ();
            var f1 = new GLib.Menu ();
            f1.append (_("Add Place…"), "app.add-place");
            f1.append (_("Use My Location…"), "win.use-location");
            file_menu.append_section (null, f1);
            var f2 = new GLib.Menu ();
            f2.append (_("Close Window"), "win.close");
            f2.append (_("Quit"), "app.quit");
            file_menu.append_section (null, f2);
            menu.append_submenu (_("File"), file_menu);
            var edit_menu = new GLib.Menu ();
            var e1 = new GLib.Menu ();
            e1.append (_("Move Place Up"), "win.move-up");
            e1.append (_("Move Place Down"), "win.move-down");
            e1.append (_("Remove Place"), "win.remove-place");
            edit_menu.append_section (null, e1);
            var e2 = new GLib.Menu ();
            e2.append (_("Settings"), "app.settings");
            edit_menu.append_section (null, e2);
            menu.append_submenu (_("Edit"), edit_menu);
            var view_menu = new GLib.Menu ();
            var v1 = new GLib.Menu ();
            v1.append (_("Previous Place"), "win.previous-place");
            v1.append (_("Next Place"), "win.next-place");
            view_menu.append_section (null, v1);
            var v2 = new GLib.Menu ();
            v2.append (_("Refresh"), "win.refresh");
            view_menu.append_section (null, v2);
            var v3 = new GLib.Menu ();
            v3.append (_("About the Data…"), "app.about-data");
            view_menu.append_section (null, v3);
            menu.append_submenu (_("View"), view_menu);
            set_menubar (menu);

            var add = new SimpleAction ("add-place", null);
            add.activate.connect (() => main_window ().open_search ());
            add_action (add);
            var locate = new SimpleAction ("use-location", null);
            locate.activate.connect (() => ((GLib.ActionGroup) main_window ()).activate_action ("use-location", null));
            add_action (locate);
            var show_place = new SimpleAction ("show-place", VariantType.STRING);
            show_place.activate.connect ((param) => main_window ().select_place (param.get_string ()));
            add_action (show_place);
            var refresh = new SimpleAction ("refresh-snapshot", null);
            refresh.activate.connect (() => refresh_snapshot.begin ());
            add_action (refresh);
            settings.changed.connect ((key) => {
                if (key == "places" || key == "selected" || key == "units") write_snapshot ();
            });
            var about = new SimpleAction ("about-data", null);
            about.activate.connect (() => show_about_data ());
            add_action (about);
            var settings_action = new SimpleAction ("settings", null);
            settings_action.activate.connect (() => {
                try {
                    Singularity.Shell.ShellService shell = Bus.get_proxy_sync (BusType.SESSION, "dev.sinty.desktop", "/dev/sinty/Shell");
                    shell.open_app_settings ("dev.sinty.weather");
                } catch (Error e) {
                    warning ("Failed to open settings: %s", e.message);
                }
            });
            add_action (settings_action);
            var quit_action = new SimpleAction ("quit", null);
            quit_action.activate.connect (() => quit ());
            add_action (quit_action);
            set_accels_for_action ("app.add-place", { "<Control>n", "<Control>f" });
            set_accels_for_action ("app.quit", { "<Control>q" });
            set_accels_for_action ("app.settings", { "<Control>comma" });
            set_accels_for_action ("win.refresh", { "<Control>r", "F5" });
            set_accels_for_action ("win.previous-place", { "<Control>Page_Up" });
            set_accels_for_action ("win.next-place", { "<Control>Page_Down" });
            set_accels_for_action ("win.close", { "<Control>w" });
        }

        public override void activate () {
            var window = main_window ();
            if (pending_action == "") return;
            string action = pending_action;
            pending_action = "";
            if (window.is_active) {
                activate_action (action, null);
                return;
            }
            ulong handler = 0;
            uint fallback = 0;
            handler = window.notify["is-active"].connect (() => {
                if (!window.is_active) return;
                window.disconnect (handler);
                handler = 0;
                if (fallback != 0) Source.remove (fallback);
                fallback = 0;
                activate_action (action, null);
            });
            fallback = Timeout.add (1500, () => {
                fallback = 0;
                if (handler != 0) window.disconnect (handler);
                handler = 0;
                activate_action (action, null);
                return Source.REMOVE;
            });
        }

        private WeatherWindow main_window () {
            var window = get_active_window () as WeatherWindow;
            if (window == null) {
                foreach (var w in get_windows ()) {
                    if (w is WeatherWindow) window = (WeatherWindow) w;
                }
            }
            if (window == null) window = new WeatherWindow (this);
            window.present ();
            return window;
        }

        public void open_place (Place place) {
            main_window ().add_place (place);
        }

        public void write_snapshot () {
            Snapshot.write (settings, service);
        }

        private async void refresh_snapshot () {
            if (refreshing) return;
            refreshing = true;
            hold ();
            var units = Units.from_setting (settings.get_string ("units"));
            int64 now = get_real_time () / 1000000;
            foreach (var place in Snapshot.places (settings)) {
                var cached = service.cached (place, units);
                if (cached != null && now - cached.fetched_at < 1500) continue;
                try {
                    yield service.forecast (place, units);
                } catch (Error e) {
                    debug ("Weather: %s", e.message);
                }
            }
            write_snapshot ();
            refreshing = false;
            release ();
        }

        public void show_about_data () {
            var dlg = new AppDialog (this, true);
            dlg.transient_for = get_active_window ();
            dlg.set_title (_("About the Data"));
            dlg.set_default_size (460, -1);
            var box = new Box (Orientation.VERTICAL, 12);
            box.margin_start = 22;
            box.margin_end = 22;
            box.margin_bottom = 20;
            string[,] sections = {
                { _("Places"), _("Places come from the GeoNames database, which lists cities, towns and villages all over the world. You can add any of them, and also any point on the map by typing its coordinates.") },
                { _("Forecasts"), _("Forecasts come from Open-Meteo, which combines national weather models. They are calculated for the exact coordinates of each place, so they do not depend on having a weather station nearby.") },
                { _("Updates"), _("Forecasts refresh every 30 minutes while Weather is open. The last forecast of each place is kept on this computer, so it is still shown when you are offline.") },
                { _("Privacy"), _("Only the coordinates of your places are sent to Open-Meteo. Your current location is found by the system location service and is used only when you ask for it.") }
            };
            for (int i = 0; i < sections.length[0]; i++) {
                var title = new Label (sections[i, 0]);
                title.xalign = 0;
                title.add_css_class ("heading");
                box.append (title);
                var text = new Label (sections[i, 1]);
                text.xalign = 0;
                text.wrap = true;
                text.max_width_chars = 52;
                box.append (text);
            }
            var link = new LinkButton.with_label ("https://open-meteo.com", _("Weather data by Open-Meteo.com, licensed CC BY 4.0"));
            link.halign = Align.START;
            box.append (link);
            dlg.content_box.append (box);
            dlg.present ();
        }

        private const string CSS = """
.weather-hero {
    padding: 22px 20px 20px 20px;
    border-radius: 22px;
    color: white;
}

.weather-hero label {
    color: white;
}

.weather-hero-place {
    font-size: 22px;
    font-weight: 700;
}

.weather-hero-sub {
    opacity: 0.85;
}

.weather-hero-temp {
    font-size: 76px;
    font-weight: 300;
}

.weather-hero-icon {
    color: white;
    -gtk-icon-shadow: 0 2px 8px alpha(black, 0.25);
}

.weather-hero-condition {
    font-size: 17px;
    font-weight: 600;
}

.weather-hero.sky-clear {
    background-image: linear-gradient(160deg, #3b8fe8, #6cc3f5);
}

.weather-hero.sky-cloudy {
    background-image: linear-gradient(160deg, #4a7fb8, #93b7d6);
}

.weather-hero.sky-overcast {
    background-image: linear-gradient(160deg, #5f6f82, #93a3b5);
}

.weather-hero.sky-fog {
    background-image: linear-gradient(160deg, #7b8794, #b3bcc6);
}

.weather-hero.sky-rain {
    background-image: linear-gradient(160deg, #3f5670, #6b87a3);
}

.weather-hero.sky-snow {
    background-image: linear-gradient(160deg, #7da6c9, #c4d8ea);
}

.weather-hero.sky-storm {
    background-image: linear-gradient(160deg, #2e2a4f, #5b4a7d);
}

.weather-hero.sky-night {
    background-image: linear-gradient(160deg, #0f1a3a, #2b3c6e);
}

.weather-hero.sky-night-cloudy {
    background-image: linear-gradient(160deg, #1c2333, #3d4759);
}

.weather-card {
    padding: 16px;
    border-radius: 18px;
    background-color: alpha(@window_fg_color, 0.05);
}

.weather-tile {
    min-height: 96px;
}

.weather-tile-value {
    font-size: 26px;
    font-weight: 600;
}

.weather-tile-small {
    font-size: 15px;
    font-weight: 600;
}

.weather-hourly {
    margin-bottom: 4px;
}
""";
    }

    public static int main (string[] args) {
        Intl.setlocale (LocaleCategory.ALL, "");
        string locale_dir = "/usr/share/locale";
        try {
            string exe = FileUtils.read_link ("/proc/self/exe");
            locale_dir = Path.build_filename (Path.get_dirname (Path.get_dirname (exe)), "share", "locale");
        } catch (Error e) {
        }
        Intl.bindtextdomain ("singularity-weather", locale_dir);
        Intl.bind_textdomain_codeset ("singularity-weather", "UTF-8");
        Intl.textdomain ("singularity-weather");
        return new WeatherApp ().run (args);
    }
}
