using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Weather {

    public class WeatherWindow : Singularity.Widgets.Window {
        private WeatherApp app;
        private AppSidebar sidebar;
        private Stack stack;
        private WelcomePage empty_page;
        private Box page;
        private Gee.ArrayList<Place> places = new Gee.ArrayList<Place> ();
        private Gee.HashMap<string, Forecast> forecasts = new Gee.HashMap<string, Forecast> ();
        private Gee.HashMap<string, SidebarRow> rows = new Gee.HashMap<string, SidebarRow> ();
        private string selected = "";
        private uint refresh_source = 0;
        private Label? status_label = null;
        private string last_error = "";

        public WeatherWindow (WeatherApp app) {
            Object (application: app);
            this.app = app;
            set_default_size (1040, 780);
            set_title (_("Weather"));

            sidebar = new AppSidebar (240);
            set_sidebar (sidebar);
            set_sidebar_visible (true);

            stack = new Stack ();
            stack.transition_type = StackTransitionType.CROSSFADE;
            empty_page = new WelcomePage ();
            empty_page.app_icon_name = "dev.sinty.weather";
            empty_page.title = _("Weather");
            empty_page.subtitle = _("Forecasts, sunrise and sunset for the places you care about.");
            empty_page.add_action ("system-search", _("Add a Place"), _("Search for any city, town or village"), () => open_search ());
            empty_page.add_action ("find-location", _("Use My Location"), _("The weather where you are now"), () => {
                open_search ();
                if (search_dialog != null) search_dialog.use_location.begin ();
            });
            stack.add_named (empty_page, "empty");

            var scroll = new ScrolledWindow ();
            scroll.hscrollbar_policy = PolicyType.NEVER;
            page = new Box (Orientation.VERTICAL, 16);
            page.margin_bottom = 24;
            page.margin_start = 24;
            page.margin_end = 24;
            scroll.child = page;
            apply_view_edge (scroll);
            stack.add_named (scroll, "page");
            set_content (stack);

            add_bubble_icon ("list-add-symbolic", _("Add Place"), () => open_search ());
            add_bubble_icon ("view-refresh-symbolic", _("Refresh"), () => refresh_all.begin (true));
            add_bubble_icon ("singularity-share-symbolic", _("Share"), () => {
                var place = find (selected);
                if (place == null || !forecasts.has_key (place.id)) return;
                var f = forecasts[place.id];
                var c = Conditions.describe (f.code, f.is_day);
                string unit = Units.from_setting (app.settings.get_string ("units")) == Units.IMPERIAL ? "°F" : "°C";
                string text = _("%s: %s, %d%s").printf (place.name, c.label, (int) Math.round (f.temperature), unit);
                Singularity.Share.text (this, text, _("Weather"));
            });

            var entries = new ActionEntry[] {
                { "use-location", () => {
                    open_search ();
                    if (search_dialog != null) search_dialog.use_location.begin ();
                } },
                { "refresh", () => refresh_all.begin (true) },
                { "remove-place", () => {
                    var place = find (selected);
                    if (place != null) remove_place (place);
                } },
                { "move-up", () => {
                    var place = find (selected);
                    if (place != null) move_place (place, -1);
                } },
                { "move-down", () => {
                    var place = find (selected);
                    if (place != null) move_place (place, 1);
                } },
                { "previous-place", () => select_offset (-1) },
                { "next-place", () => select_offset (1) },
                { "close", () => close () }
            };
            add_action_entries (entries, this);

            load_places ();
            app.settings.changed["units"].connect (() => {
                forecasts.clear ();
                refresh_all.begin (true);
            });
            refresh_source = Timeout.add_seconds (1800, () => {
                refresh_all.begin (false);
                return Source.CONTINUE;
            });
            close_request.connect (() => {
                if (refresh_source != 0) Source.remove (refresh_source);
                refresh_source = 0;
                return false;
            });
            refresh_all.begin (false);
        }

        private Units units () {
            return Units.from_setting (app.settings.get_string ("units"));
        }

        private void load_places () {
            places.clear ();
            var value = app.settings.get_value ("places");
            for (size_t i = 0; i < value.n_children (); i++) {
                string name, region, country;
                double lat, lon;
                value.get_child (i, "(sssdd)", out name, out region, out country, out lat, out lon);
                places.add (new Place (name, region, country, lat, lon));
            }
            selected = app.settings.get_string ("selected");
            if (find (selected) == null && places.size > 0) selected = places[0].id;
            foreach (var p in places) {
                var cached = app.service.cached (p, units ());
                if (cached != null) forecasts[p.id] = cached;
            }
            rebuild_sidebar ();
            show_selected ();
        }

        private void save_places () {
            var builder = new VariantBuilder (new VariantType ("a(sssdd)"));
            foreach (var p in places) builder.add ("(sssdd)", p.name, p.region, p.country, p.latitude, p.longitude);
            app.settings.set_value ("places", builder.end ());
            app.settings.set_string ("selected", selected);
        }

        private Place? find (string id) {
            foreach (var p in places) if (p.id == id) return p;
            return null;
        }

        public void add_place (Place place) {
            var existing = find (place.id);
            if (existing == null) {
                places.add (place);
                existing = place;
            }
            selected = existing.id;
            save_places ();
            rebuild_sidebar ();
            show_selected ();
            refresh_place.begin (existing, true);
        }

        private void remove_place (Place place) {
            places.remove (place);
            forecasts.unset (place.id);
            if (selected == place.id) selected = places.size > 0 ? places[0].id : "";
            save_places ();
            rebuild_sidebar ();
            show_selected ();
        }

        private void move_place (Place place, int delta) {
            int index = places.index_of (place);
            int target = (index + delta).clamp (0, places.size - 1);
            if (index == target) return;
            places.remove_at (index);
            places.insert (target, place);
            save_places ();
            rebuild_sidebar ();
        }

        private void rebuild_sidebar () {
            rows.clear ();
            Widget? child;
            while ((child = sidebar.box.get_first_child ()) != null) sidebar.box.remove (child);
            set_sidebar_visible (places.size > 0);
            if (places.size > 0) sidebar.box.append (new SidebarSectionLabel (_("Places")));
            foreach (var place in places) {
                var f = forecasts[place.id];
                string icon = "weather-few-clouds";
                if (f != null) {
                    var cond = Conditions.describe (f.code, f.is_day);
                    icon = cond.icon;
                }
                string text = f != null ? "%s  %s".printf (place.name, Format.temperature (f.temperature)) : place.name;
                var row = new SidebarRow (icon + "-symbolic", text);
                row.tooltip_text = place.subtitle () != "" ? "%s\n%s".printf (place.name, place.subtitle ()) : place.name;
                var cap = place;
                row.clicked.connect (() => {
                    selected = cap.id;
                    app.settings.set_string ("selected", selected);
                    sync_active ();
                    show_selected ();
                });
                var right = new GestureClick ();
                right.button = Gdk.BUTTON_SECONDARY;
                right.pressed.connect ((n, x, y) => place_menu (row, cap, x, y));
                row.add_controller (right);
                rows[place.id] = row;
                sidebar.box.append (row);
            }
            sync_active ();
        }

        private void place_menu (Widget anchor, Place place, double x, double y) {
            var menu = new ContextMenu (anchor);
            Gdk.Rectangle rect = { (int) x, (int) y, 1, 1 };
            menu.set_pointing_to (rect);
            int index = places.index_of (place);
            if (index > 0) menu.add_item (_("Move Up"), "go-up-symbolic", () => move_place (place, -1));
            if (index < places.size - 1) menu.add_item (_("Move Down"), "go-down-symbolic", () => move_place (place, 1));
            menu.add_item (_("Remove"), "user-trash-symbolic", () => remove_place (place), "destructive-action");
            menu.closed.connect (() => Idle.add (() => {
                menu.unparent ();
                return Source.REMOVE;
            }));
            menu.popup ();
        }

        private void sync_active () {
            foreach (var entry in rows.entries) entry.value.set_active (entry.key == selected);
            int index = places.index_of (find (selected));
            ((SimpleAction) lookup_action ("refresh")).set_enabled (places.size > 0);
            ((SimpleAction) lookup_action ("remove-place")).set_enabled (index >= 0);
            ((SimpleAction) lookup_action ("move-up")).set_enabled (index > 0);
            ((SimpleAction) lookup_action ("move-down")).set_enabled (index >= 0 && index < places.size - 1);
            ((SimpleAction) lookup_action ("previous-place")).set_enabled (index > 0);
            ((SimpleAction) lookup_action ("next-place")).set_enabled (index >= 0 && index < places.size - 1);
        }

        private void select_offset (int delta) {
            int index = places.index_of (find (selected)) + delta;
            if (index < 0 || index >= places.size) return;
            selected = places[index].id;
            app.settings.set_string ("selected", selected);
            sync_active ();
            show_selected ();
        }

        private async void refresh_all (bool force) {
            foreach (var place in places) yield refresh_place (place, force);
        }

        private async void refresh_place (Place place, bool force) {
            var existing = forecasts[place.id];
            if (!force && existing != null && get_real_time () / 1000000 - existing.fetched_at < 900) return;
            try {
                forecasts[place.id] = yield app.service.forecast (place, units ());
                last_error = "";
            } catch (Error e) {
                last_error = e.message;
                if (existing == null) forecasts.unset (place.id);
            }
            rebuild_sidebar ();
            if (place.id == selected) show_selected ();
            app.write_snapshot ();
        }

        public void select_place (string id) {
            if (find (id) == null) return;
            selected = id;
            app.settings.set_string ("selected", selected);
            sync_active ();
            show_selected ();
        }

        private void clear_page () {
            Widget? child;
            while ((child = page.get_first_child ()) != null) page.remove (child);
        }

        private void show_selected () {
            var place = find (selected);
            if (place == null) {
                stack.visible_child_name = "empty";
                return;
            }
            stack.visible_child_name = "page";
            clear_page ();
            var f = forecasts[place.id];
            if (f == null) {
                var loading = new StatusPage ();
                loading.icon_name = last_error != "" ? "network-error" : "dev.sinty.weather";
                loading.title = last_error != "" ? _("Weather Unavailable") : _("Loading Forecast");
                loading.description = last_error != "" ? last_error : place.name;
                loading.vexpand = true;
                if (last_error != "") {
                    var retry = new Button.with_label (_("Try Again"));
                    retry.add_css_class ("pill");
                    retry.add_css_class ("suggested-action");
                    retry.halign = Align.CENTER;
                    retry.clicked.connect (() => refresh_all.begin (true));
                    loading.child = retry;
                }
                page.append (loading);
                return;
            }
            build_page (place, f);
        }

        private void build_page (Place place, Forecast f) {
            var u = units ();
            var cond = Conditions.describe (f.code, f.is_day);
            var today = f.today ();

            var hero = new Box (Orientation.VERTICAL, 2);
            hero.add_css_class ("weather-hero");
            hero.add_css_class ("sky-" + cond.sky);
            var name = new Label (place.name);
            name.add_css_class ("weather-hero-place");
            hero.append (name);
            var sub = new Label (place.subtitle () != "" ? place.subtitle () : place.coordinates ());
            sub.add_css_class ("weather-hero-sub");
            hero.append (sub);
            var temp_row = new Box (Orientation.HORIZONTAL, 14);
            temp_row.halign = Align.CENTER;
            temp_row.margin_top = 6;
            var icon = new Image.from_icon_name (cond.icon);
            icon.pixel_size = 64;
            icon.add_css_class ("weather-hero-icon");
            temp_row.append (icon);
            var temp = new Label (Format.temperature (f.temperature));
            temp.add_css_class ("weather-hero-temp");
            temp_row.append (temp);
            hero.append (temp_row);
            var condition = new Label (cond.label);
            condition.add_css_class ("weather-hero-condition");
            hero.append (condition);
            if (today != null) {
                var range = new Label (_("H %s  L %s  Feels like %s").printf (Format.temperature (today.high), Format.temperature (today.low), Format.temperature (f.feels_like)));
                range.add_css_class ("weather-hero-sub");
                hero.append (range);
            }
            page.append (hero);

            var hourly_card = card (_("Next 24 Hours"));
            var strip = new HourlyStrip ();
            var hours = new Gee.ArrayList<Hour?> ();
            for (int i = 0; i < f.hours.size && i < 25; i++) {
                Hour h = f.hours[i];
                if (i == 0) {
                    h.temperature = f.temperature;
                    h.code = f.code;
                    h.day = f.is_day;
                }
                hours.add (h);
            }
            strip.set_hours (hours);
            var hscroll = new ScrolledWindow ();
            hscroll.vscrollbar_policy = PolicyType.NEVER;
            hscroll.hscrollbar_policy = PolicyType.AUTOMATIC;
            hscroll.child = strip;
            hourly_card.append (hscroll);
            var legend = new Label (_("Bars show the chance of rain"));
            legend.xalign = 0;
            legend.add_css_class ("dim-label");
            legend.add_css_class ("caption");
            hourly_card.append (legend);
            page.append (hourly_card);

            var daily_card = card (_("Next %d Days").printf (f.days.size));
            var grid = new Grid ();
            grid.column_spacing = 14;
            grid.row_spacing = 10;
            double lo = double.MAX, hi = -double.MAX;
            foreach (var d in f.days) {
                lo = double.min (lo, d.low);
                hi = double.max (hi, d.high);
            }
            for (int i = 0; i < f.days.size; i++) {
                var d = f.days[i];
                var dc = Conditions.describe (d.code, true);
                var day_name = new Label (Format.weekday (d.date, f.current_time));
                day_name.xalign = 0;
                day_name.width_chars = 10;
                if (i == 0) day_name.add_css_class ("heading");
                grid.attach (day_name, 0, i, 1, 1);
                var di = new Image.from_icon_name (dc.icon);
                di.pixel_size = 20;
                di.tooltip_text = dc.label;
                grid.attach (di, 1, i, 1, 1);
                var rain = new Label (d.precipitation_probability >= 20 ? "%d%%".printf (d.precipitation_probability) : "");
                rain.width_chars = 4;
                rain.xalign = 1;
                rain.add_css_class ("dim-label");
                rain.add_css_class ("caption");
                rain.tooltip_text = _("Chance of rain");
                grid.attach (rain, 2, i, 1, 1);
                var low = new Label (Format.temperature (d.low));
                low.add_css_class ("dim-label");
                low.width_chars = 4;
                low.xalign = 1;
                grid.attach (low, 3, i, 1, 1);
                grid.attach (new RangeBar (lo, hi, d.low, d.high, i == 0 ? f.temperature : double.NAN, u == Units.IMPERIAL), 4, i, 1, 1);
                var high = new Label (Format.temperature (d.high));
                high.width_chars = 4;
                high.xalign = 0;
                grid.attach (high, 5, i, 1, 1);
            }
            daily_card.append (grid);
            page.append (daily_card);

            var tiles = new TileGrid ();
            if (today != null) tiles.append (sun_tile (f, today));
            tiles.append (wind_tile (f, u));
            if (f.uv >= 0) tiles.append (simple_tile (_("UV Index"), "%.0f".printf (f.uv), Conditions.uv_level (f.uv),
                today != null ? _("Today's peak %.0f").printf (today.uv_max) : null));
            tiles.append (simple_tile (_("Humidity"), "%d%%".printf (f.humidity), null, null));
            tiles.append (simple_tile (_("Feels Like"), Format.temperature (f.feels_like),
                (f.feels_like - f.temperature).abs () < 1.5 ? _("Similar to the actual temperature") : (f.feels_like < f.temperature ? _("Wind makes it feel colder") : _("Humidity makes it feel warmer")), null));
            if (today != null) tiles.append (simple_tile (_("Precipitation"), "%.1f %s".printf (today.precipitation, u.precipitation_symbol ()), _("Expected today"), null));
            tiles.append (simple_tile (_("Pressure"), "%.0f hPa".printf (f.pressure), null, null));
            if (f.visibility >= 0) {
                string vis = u == Units.IMPERIAL ? "%.0f mi".printf (f.visibility / 1609.34) : (f.visibility >= 10000 ? "%.0f km".printf (f.visibility / 1000) : "%.1f km".printf (f.visibility / 1000));
                tiles.append (simple_tile (_("Visibility"), vis, null, null));
            }
            page.append (tiles);

            var updated = new DateTime.from_unix_local (f.fetched_at);
            string footer = _("Updated at %s").printf (updated.format ("%H:%M"));
            if (last_error != "") footer = _("Offline, showing the forecast from %s").printf (updated.format ("%-d %b %H:%M"));
            status_label = new Label ("%s · %s".printf (footer, _("Data from Open-Meteo.com, CC BY 4.0")));
            status_label.add_css_class ("dim-label");
            status_label.add_css_class ("caption");
            status_label.wrap = true;
            status_label.margin_top = 4;
            page.append (status_label);
            var about = new Button.with_label (_("Where does this data come from?"));
            about.add_css_class ("flat");
            about.halign = Align.CENTER;
            about.clicked.connect (() => app.show_about_data ());
            page.append (about);
        }

        private class TileGrid : Grid {
            private int count = 0;

            public TileGrid () {
                column_spacing = 16;
                row_spacing = 16;
                column_homogeneous = true;
            }

            public new void append (Widget tile) {
                tile.valign = Align.FILL;
                attach (tile, count % 2, count / 2, 1, 1);
                count++;
            }
        }

        private Box card (string title) {
            var box = new Box (Orientation.VERTICAL, 10);
            box.add_css_class ("weather-card");
            var heading = new Label (title);
            heading.xalign = 0;
            heading.add_css_class ("heading");
            box.append (heading);
            return box;
        }

        private Widget simple_tile (string title, string value, string? detail, string? extra) {
            var box = card (title);
            box.add_css_class ("weather-tile");
            var v = new Label (value);
            v.xalign = 0;
            v.add_css_class ("weather-tile-value");
            box.append (v);
            foreach (string? text in new string?[] { detail, extra }) {
                if (text == null) continue;
                var l = new Label (text);
                l.xalign = 0;
                l.wrap = true;
                l.add_css_class ("dim-label");
                box.append (l);
            }
            return box;
        }

        private Widget sun_tile (Forecast f, Day today) {
            var box = card (_("Sunrise and Sunset"));
            box.add_css_class ("weather-tile");
            var arc = new SunArc ();
            arc.set_progress (Forecast.sun_progress (f.current_time, today.sunrise, today.sunset));
            box.append (arc);
            var times = new Box (Orientation.HORIZONTAL, 0);
            var rise = new Label (today.sunrise != null ? Format.hour (today.sunrise) : "--");
            rise.hexpand = true;
            rise.xalign = 0;
            rise.add_css_class ("weather-tile-small");
            var set = new Label (today.sunset != null ? Format.hour (today.sunset) : "--");
            set.xalign = 1;
            set.add_css_class ("weather-tile-small");
            times.append (rise);
            times.append (set);
            box.append (times);
            string daylight = _("Daylight %s").printf (Format.duration (today.daylight_seconds));
            if (f.days.size > 1 && today.daylight_seconds > 0) {
                int change = (int) Math.round ((f.days[1].daylight_seconds - today.daylight_seconds) / 60.0);
                if (change > 0) daylight += ", " + ngettext ("tomorrow %d minute longer", "tomorrow %d minutes longer", change).printf (change);
                else if (change < 0) daylight += ", " + ngettext ("tomorrow %d minute shorter", "tomorrow %d minutes shorter", -change).printf (-change);
            }
            var d = new Label (daylight);
            d.xalign = 0;
            d.wrap = true;
            d.add_css_class ("dim-label");
            box.append (d);
            return box;
        }

        private Widget wind_tile (Forecast f, Units u) {
            var box = card (_("Wind"));
            box.add_css_class ("weather-tile");
            var row = new Box (Orientation.HORIZONTAL, 14);
            var compass = new Compass ();
            compass.set_direction (f.wind_direction);
            row.append (compass);
            var texts = new Box (Orientation.VERTICAL, 2);
            texts.valign = Align.CENTER;
            var v = new Label ("%.0f %s".printf (f.wind_speed, u.speed_symbol ()));
            v.xalign = 0;
            v.add_css_class ("weather-tile-value");
            texts.append (v);
            var from = new Label (_("From %s").printf (Conditions.compass (f.wind_direction)));
            from.xalign = 0;
            from.add_css_class ("dim-label");
            texts.append (from);
            if (f.wind_gusts > f.wind_speed + 5) {
                var gusts = new Label (_("Gusts %.0f %s").printf (f.wind_gusts, u.speed_symbol ()));
                gusts.xalign = 0;
                gusts.add_css_class ("dim-label");
                texts.append (gusts);
            }
            row.append (texts);
            box.append (row);
            return box;
        }

        private SearchDialog? search_dialog;

        public void open_search () {
            var dialog = new SearchDialog (app);
            dialog.transient_for = this;
            dialog.chosen.connect ((place) => add_place (place));
            dialog.close_request.connect (() => {
                search_dialog = null;
                return false;
            });
            search_dialog = dialog;
            dialog.present ();
        }
    }

    public class SearchDialog : AppDialog {
        private WeatherApp app;
        private Gtk.SearchEntry entry;
        private ListBox results;
        private Label status;
        private uint pending = 0;
        private int generation = 0;

        public signal void chosen (Place place);

        public SearchDialog (WeatherApp app) {
            base (app, true);
            this.app = app;
            set_title (_("Add Place"));
            set_default_size (480, 560);
            var box = new Box (Orientation.VERTICAL, 10);
            box.margin_start = 18;
            box.margin_end = 18;
            box.margin_bottom = 16;
            box.margin_top = 4;
            entry = new Gtk.SearchEntry ();
            entry.placeholder_text = _("City, town, village or coordinates");
            entry.input_hints = InputHints.NO_SPELLCHECK | InputHints.NO_EMOJI;
            entry.search_changed.connect (queue_search);
            entry.activate.connect (() => {
                var first = results.get_row_at_index (0);
                if (first != null) first.activate ();
            });
            box.append (entry);
            var here = new Button ();
            var here_box = new Box (Orientation.HORIZONTAL, 8);
            here_box.append (new Image.from_icon_name ("find-location-symbolic"));
            here_box.append (new Label (_("Use My Current Location")));
            here.child = here_box;
            here.add_css_class ("flat");
            here.halign = Align.START;
            here.clicked.connect (() => use_location.begin ());
            box.append (here);
            status = new Label ("");
            status.wrap = true;
            status.xalign = 0;
            status.add_css_class ("dim-label");
            status.visible = false;
            box.append (status);
            results = new ListBox ();
            results.add_css_class ("boxed-list");
            results.selection_mode = SelectionMode.NONE;
            results.row_activated.connect ((row) => {
                var place = row.get_data<Place> ("place");
                if (place != null) {
                    chosen (place);
                    close_dialog ();
                }
            });
            var scroll = new ScrolledWindow ();
            scroll.vexpand = true;
            scroll.hscrollbar_policy = PolicyType.NEVER;
            scroll.child = results;
            box.append (scroll);
            var help = new Label (_("Any place in the world can be added: the list comes from the GeoNames database, and the forecast is calculated for the exact coordinates, so no nearby weather station is needed. If a small place is missing, search for the nearest town or type its coordinates, for example 45.46, 9.19."));
            help.wrap = true;
            help.xalign = 0;
            help.add_css_class ("dim-label");
            help.add_css_class ("caption");
            box.append (help);
            content_box.append (box);
            map.connect (() => entry.grab_focus ());
        }

        private void queue_search () {
            if (pending != 0) Source.remove (pending);
            pending = Timeout.add (350, () => {
                pending = 0;
                search.begin (entry.text);
                return Source.REMOVE;
            });
        }

        private void show_status (string text) {
            status.label = text;
            status.visible = text != "";
        }

        private void clear_results () {
            Widget? child;
            while ((child = results.get_first_child ()) != null) results.remove (child);
        }

        private async void search (string text) {
            int gen = ++generation;
            if (text.strip ().length < 2) {
                clear_results ();
                show_status ("");
                return;
            }
            show_status (_("Searching"));
            Gee.List<Place> found;
            try {
                found = yield app.service.search (text);
            } catch (Error e) {
                if (gen == generation) show_status (e.message);
                return;
            }
            if (gen != generation) return;
            clear_results ();
            show_status (found.size == 0 ? _("No places found. Try a nearby town or type coordinates.") : "");
            foreach (var place in found) {
                var row = new ListBoxRow ();
                var rbox = new Box (Orientation.VERTICAL, 2);
                rbox.margin_top = 8;
                rbox.margin_bottom = 8;
                rbox.margin_start = 12;
                rbox.margin_end = 12;
                var n = new Label (place.name);
                n.xalign = 0;
                rbox.append (n);
                var s = new Label (place.subtitle () != "" ? "%s · %s".printf (place.subtitle (), place.coordinates ()) : place.coordinates ());
                s.xalign = 0;
                s.add_css_class ("dim-label");
                s.add_css_class ("caption");
                rbox.append (s);
                row.child = rbox;
                row.set_data<Place> ("place", place);
                results.append (row);
            }
        }

        public async void use_location () {
            show_status (_("Finding your location"));
            try {
                var place = yield new Locator ().locate ();
                chosen (place);
                close_dialog ();
            } catch (Error e) {
                show_status (_("Your location is not available: %s. Search for your town instead.").printf (e.message));
            }
        }
    }
}
