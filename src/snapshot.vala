namespace Singularity.Apps.Weather {

    public class Snapshot : Object {
        public static string path () {
            return Path.build_filename (Environment.get_user_cache_dir (), "singularity-weather", "snapshot.json");
        }

        public static Gee.List<Place> places (GLib.Settings settings) {
            var list = new Gee.ArrayList<Place> ();
            var iter = settings.get_value ("places").iterator ();
            string name, region, country;
            double lat, lon;
            while (iter.next ("(sssdd)", out name, out region, out country, out lat, out lon)) {
                list.add (new Place (name, region, country, lat, lon));
            }
            return list;
        }

        public static void write (GLib.Settings settings, WeatherService service) {
            var units = Units.from_setting (settings.get_string ("units"));
            var list = places (settings);
            string selected = settings.get_string ("selected");
            bool known = false;
            foreach (var p in list) if (p.id == selected) known = true;
            if (!known) selected = list.size > 0 ? list[0].id : "";

            var b = new Json.Builder ();
            b.begin_object ();
            b.set_member_name ("version").add_int_value (1);
            b.set_member_name ("units").add_string_value (units.temperature_symbol ());
            b.set_member_name ("selected").add_string_value (selected);
            b.set_member_name ("written_at").add_int_value (get_real_time () / 1000000);
            b.set_member_name ("places").begin_array ();
            foreach (var place in list) {
                b.begin_object ();
                b.set_member_name ("id").add_string_value (place.id);
                b.set_member_name ("name").add_string_value (place.name);
                b.set_member_name ("subtitle").add_string_value (place.subtitle ());
                var f = service.cached (place, units);
                if (f != null) add_forecast (b, f);
                b.end_object ();
            }
            b.end_array ();
            b.end_object ();

            var gen = new Json.Generator ();
            gen.root = b.get_root ();
            try {
                string file = path ();
                DirUtils.create_with_parents (Path.get_dirname (file), 0700);
                FileUtils.set_contents (file, gen.to_data (null));
            } catch (Error e) {
                warning ("Weather: cannot write the snapshot: %s", e.message);
            }
        }

        private static void add_forecast (Json.Builder b, Forecast f) {
            var cond = Conditions.describe (f.code, f.is_day);
            b.set_member_name ("fetched_at").add_int_value (f.fetched_at);
            b.set_member_name ("temperature").add_string_value (Format.temperature (f.temperature));
            b.set_member_name ("condition").add_string_value (cond.label);
            b.set_member_name ("icon").add_string_value (cond.icon);
            var today = f.today ();
            if (today != null) {
                b.set_member_name ("high").add_string_value (Format.temperature (today.high));
                b.set_member_name ("low").add_string_value (Format.temperature (today.low));
            }
            b.set_member_name ("hours").begin_array ();
            foreach (var h in f.hours) {
                var hc = Conditions.describe (h.code, h.day);
                b.begin_object ();
                b.set_member_name ("t").add_int_value (h.time.to_unix ());
                b.set_member_name ("label").add_string_value (Format.hour (h.time));
                b.set_member_name ("icon").add_string_value (hc.icon);
                b.set_member_name ("temperature").add_string_value (Format.temperature (h.temperature));
                b.end_object ();
            }
            b.end_array ();
            b.set_member_name ("days").begin_array ();
            foreach (var d in f.days) {
                var dc = Conditions.describe (d.code, true);
                b.begin_object ();
                b.set_member_name ("t").add_int_value (d.date.to_unix ());
                b.set_member_name ("label").add_string_value (d.date.format ("%a"));
                b.set_member_name ("icon").add_string_value (dc.icon);
                b.set_member_name ("high").add_string_value (Format.temperature (d.high));
                b.set_member_name ("low").add_string_value (Format.temperature (d.low));
                b.end_object ();
            }
            b.end_array ();
        }
    }
}
