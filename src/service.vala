namespace Singularity.Apps.Weather {

    public class WeatherService : Object {
        private const string FORECAST = "https://api.open-meteo.com/v1/forecast";
        private const string GEOCODING = "https://geocoding-api.open-meteo.com/v1/search";
        private Soup.Session session;

        public WeatherService () {
            session = new Soup.Session ();
            session.timeout = 20;
            session.user_agent = "Singularity-Weather";
        }

        private static string cache_dir () {
            return Path.build_filename (Environment.get_user_cache_dir (), "singularity-weather");
        }

        private static string cache_file (Place place, Units units) {
            return Path.build_filename (cache_dir (), "%s-%s.json".printf (place.id.replace (",", "_"), units == Units.IMPERIAL ? "i" : "m"));
        }

        public static string forecast_url (Place place, Units units) {
            var sb = new StringBuilder (FORECAST);
            sb.append_printf ("?latitude=%s&longitude=%s", fmt (place.latitude), fmt (place.longitude));
            sb.append ("&current=temperature_2m,apparent_temperature,relative_humidity_2m,is_day,weather_code,wind_speed_10m,wind_direction_10m,wind_gusts_10m,pressure_msl,precipitation");
            sb.append ("&hourly=temperature_2m,precipitation_probability,weather_code,is_day,visibility,uv_index");
            sb.append ("&daily=weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,daylight_duration,uv_index_max,precipitation_sum,precipitation_probability_max");
            sb.append ("&timezone=auto&forecast_days=10&forecast_hours=48");
            if (units == Units.IMPERIAL) sb.append ("&temperature_unit=fahrenheit&wind_speed_unit=mph&precipitation_unit=inch");
            return sb.str;
        }

        private static string fmt (double value) {
            char[] buffer = new char[double.DTOSTR_BUF_SIZE];
            return value.format (buffer, "%.4f");
        }

        private async string get (string url) throws Error {
            var msg = new Soup.Message ("GET", url);
            if (msg == null) throw new IOError.INVALID_ARGUMENT ("Invalid address");
            var bytes = yield session.send_and_read_async (msg, Priority.DEFAULT, null);
            if (msg.status_code == 429) throw new IOError.BUSY (_("The weather service is busy, try again in a minute"));
            if (msg.status_code < 200 || msg.status_code >= 300) {
                throw new IOError.FAILED (_("The weather service answered with error %u").printf (msg.status_code));
            }
            unowned uint8[] data = bytes.get_data ();
            var sb = new StringBuilder.sized (data.length + 1);
            if (data.length > 0) sb.append_len ((string) data, data.length);
            return sb.str;
        }

        public Forecast? cached (Place place, Units units) {
            string text;
            try {
                FileUtils.get_contents (cache_file (place, units), out text);
                return Forecast.parse (text);
            } catch (Error e) {
                return null;
            }
        }

        public async Forecast forecast (Place place, Units units) throws Error {
            string text = yield get (forecast_url (place, units));
            int64 now = get_real_time () / 1000000;
            int brace = text.last_index_of ("}");
            string stamped = brace > 0 ? text.substring (0, brace) + ",\"fetched_at\":%lld}".printf (now) : text;
            var forecast = Forecast.parse (stamped);
            try {
                DirUtils.create_with_parents (cache_dir (), 0700);
                FileUtils.set_contents (cache_file (place, units), stamped);
            } catch (Error e) {
            }
            return forecast;
        }

        public async Forecast current (Place place, Units units, Cancellable? cancellable = null) throws Error {
            var sb = new StringBuilder (FORECAST);
            sb.append_printf ("?latitude=%s&longitude=%s", fmt (place.latitude), fmt (place.longitude));
            sb.append ("&current=temperature_2m,is_day,weather_code&hourly=temperature_2m,weather_code&forecast_hours=1&daily=temperature_2m_max,temperature_2m_min,weather_code&timezone=auto&forecast_days=1");
            if (units == Units.IMPERIAL) sb.append ("&temperature_unit=fahrenheit");
            string text = yield get (sb.str);
            if (cancellable != null) cancellable.set_error_if_cancelled ();
            return Forecast.parse (text);
        }

        public static string language () {
            string lang = Intl.get_language_names ()[0];
            if (lang == null || lang == "C" || lang == "POSIX") return "en";
            return lang.split ("_")[0].split (".")[0];
        }

        public async Gee.List<Place> search (string query) throws Error {
            var results = new Gee.ArrayList<Place> ();
            var coords = Place.from_coordinates (query);
            if (coords != null) {
                results.add (coords);
                return results;
            }
            string url = "%s?name=%s&count=20&format=json&language=%s".printf (GEOCODING, Uri.escape_string (query.strip (), null, true), language ());
            string text = yield get (url);
            results.add_all (rank (parse_places (text), query));
            return results;
        }

        private static string fold (string text) {
            return text.normalize (-1, NormalizeMode.NFKD).casefold ().replace ("\u0301", "").replace ("\u0300", "").replace ("\u0308", "").replace ("\u0302", "").replace ("\u0303", "").replace ("\u030c", "").replace ("\u0327", "").strip ();
        }

        public static Gee.List<Place> rank (Gee.List<Place> places, string query) {
            string q = fold (query);
            var list = new Gee.ArrayList<Place> ();
            list.add_all (places);
            list.sort ((a, b) => {
                int ea = fold (a.name) == q ? 0 : 1;
                int eb = fold (b.name) == q ? 0 : 1;
                if (ea != eb) return ea - eb;
                return a.population > b.population ? -1 : (a.population < b.population ? 1 : 0);
            });
            return list;
        }

        public static Gee.List<Place> parse_places (string text) throws Error {
            var list = new Gee.ArrayList<Place> ();
            var parser = new Json.Parser ();
            parser.load_from_data (text);
            var root = parser.get_root ();
            if (root == null || root.get_node_type () != Json.NodeType.OBJECT) return list;
            var obj = root.get_object ();
            if (!obj.has_member ("results")) return list;
            foreach (var node in obj.get_array_member ("results").get_elements ()) {
                var r = node.get_object ();
                string name = r.has_member ("name") ? r.get_string_member ("name") : "";
                string region = r.has_member ("admin1") ? r.get_string_member ("admin1") : "";
                string country = r.has_member ("country") ? r.get_string_member ("country") : "";
                if (name == "" || !r.has_member ("latitude")) continue;
                var place = new Place (name, region, country, r.get_double_member ("latitude"), r.get_double_member ("longitude"));
                if (r.has_member ("population")) place.population = r.get_int_member ("population");
                list.add (place);
            }
            return list;
        }
    }

    public class Locator : Object {
        private DBusConnection? bus = null;
        private string? client_path = null;
        private uint subscription = 0;

        public async Place locate () throws Error {
            bus = yield Bus.get (BusType.SYSTEM);
            var reply = yield bus.call ("org.freedesktop.GeoClue2", "/org/freedesktop/GeoClue2/Manager",
                "org.freedesktop.GeoClue2.Manager", "GetClient", null, new VariantType ("(o)"), DBusCallFlags.NONE, 10000);
            reply.get ("(o)", out client_path);
            yield set_prop ("DesktopId", new Variant.string ("dev.sinty.weather"));
            yield set_prop ("RequestedAccuracyLevel", new Variant.uint32 (4));
            Place? found = null;
            Error? failure = null;
            SourceFunc callback = locate.callback;
            bool done = false;
            subscription = bus.signal_subscribe ("org.freedesktop.GeoClue2", "org.freedesktop.GeoClue2.Client", "LocationUpdated",
                client_path, null, DBusSignalFlags.NONE, (conn, sender, path, iface, name, parameters) => {
                    string location_path;
                    parameters.get ("(oo)", null, out location_path);
                    read_location.begin (location_path, (obj, res) => {
                        try {
                            found = read_location.end (res);
                        } catch (Error e) {
                            failure = e;
                        }
                        if (!done) {
                            done = true;
                            Idle.add ((owned) callback);
                        }
                    });
                });
            var timeout = Timeout.add_seconds (20, () => {
                if (!done) {
                    done = true;
                    failure = new IOError.TIMED_OUT (_("Your location could not be found"));
                    Idle.add ((owned) callback);
                }
                return Source.REMOVE;
            });
            yield bus.call ("org.freedesktop.GeoClue2", client_path, "org.freedesktop.GeoClue2.Client", "Start", null, null, DBusCallFlags.NONE, 10000);
            yield;
            if (!done) Source.remove (timeout);
            stop ();
            if (failure != null) throw failure;
            return found;
        }

        private async void set_prop (string name, Variant value) throws Error {
            yield bus.call ("org.freedesktop.GeoClue2", client_path, "org.freedesktop.DBus.Properties", "Set",
                new Variant ("(ssv)", "org.freedesktop.GeoClue2.Client", name, value), null, DBusCallFlags.NONE, 5000);
        }

        private async Place read_location (string path) throws Error {
            var reply = yield bus.call ("org.freedesktop.GeoClue2", path, "org.freedesktop.DBus.Properties", "GetAll",
                new Variant ("(s)", "org.freedesktop.GeoClue2.Location"), new VariantType ("(a{sv})"), DBusCallFlags.NONE, 5000);
            var props = reply.get_child_value (0);
            double lat = props.lookup_value ("Latitude", VariantType.DOUBLE).get_double ();
            double lon = props.lookup_value ("Longitude", VariantType.DOUBLE).get_double ();
            return new Place (_("Current Location"), "", "", lat, lon);
        }

        private void stop () {
            if (bus == null || client_path == null) return;
            if (subscription != 0) bus.signal_unsubscribe (subscription);
            subscription = 0;
            bus.call.begin ("org.freedesktop.GeoClue2", client_path, "org.freedesktop.GeoClue2.Client", "Stop", null, null, DBusCallFlags.NONE, 5000, null);
        }
    }
}
