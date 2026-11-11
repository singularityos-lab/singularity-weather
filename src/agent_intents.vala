namespace Singularity.Apps.Weather {

    internal class WeatherIntents : Object {
        private const string PLACE = "{\"type\":\"object\",\"properties\":{\"place\":{\"type\":\"string\"}}}";

        private static string text (Json.Object args, string key) {
            return args.has_member (key) ? args.get_string_member (key).strip () : "";
        }

        private static Units units (WeatherApp app) {
            return Units.from_setting (app.settings.get_string ("units"));
        }

        private static WeatherWindow? open_window (WeatherApp app) {
            foreach (var w in app.get_windows ()) {
                if (w is WeatherWindow) return (WeatherWindow) w;
            }
            return null;
        }

        private static async Place resolve (WeatherApp app, string query) throws Error {
            var saved = Snapshot.places (app.settings);
            if (query == "") {
                string selected = app.settings.get_string ("selected");
                foreach (var p in saved) if (p.id == selected) return p;
                if (saved.size > 0) return saved[0];
                throw new IOError.NOT_FOUND ("no place is saved: give a place");
            }
            string want = query.casefold ();
            foreach (var p in saved) if (p.name.casefold () == want) return p;
            foreach (var p in saved) if (p.name.casefold ().has_prefix (want)) return p;
            var found = yield app.service.search (query);
            if (found.size == 0) throw new IOError.NOT_FOUND ("no place matches %s", query);
            return found[0];
        }

        private static async Forecast fetch (WeatherApp app, Place place) throws Error {
            try {
                return yield app.service.forecast (place, units (app));
            } catch (Error e) {
                var cached = app.service.cached (place, units (app));
                if (cached == null) throw e;
                return cached;
            }
        }

        private static double tenth (double v) {
            return Math.round (v * 10) / 10;
        }

        private static void place_members (Json.Builder b, Place place, Forecast? f) {
            b.set_member_name ("place").add_string_value (place.name);
            b.set_member_name ("region").add_string_value (place.subtitle ());
            b.set_member_name ("id").add_string_value (place.id);
            if (f != null) {
                b.set_member_name ("timezone").add_string_value (f.timezone_name);
                b.set_member_name ("fetched_at").add_string_value (new DateTime.from_unix_local (f.fetched_at).format_iso8601 ());
            }
        }

        private static void day_members (Json.Builder b, Day d) {
            var c = Conditions.describe (d.code, true);
            b.set_member_name ("date").add_string_value (d.date.format ("%Y-%m-%d"));
            b.set_member_name ("condition").add_string_value (c.label);
            b.set_member_name ("high").add_double_value (Math.round (d.high));
            b.set_member_name ("low").add_double_value (Math.round (d.low));
            b.set_member_name ("precipitation_chance").add_int_value (d.precipitation_probability);
            b.set_member_name ("precipitation").add_double_value (tenth (d.precipitation));
            if (d.uv_max >= 0) b.set_member_name ("uv").add_double_value (tenth (d.uv_max));
            if (d.sunrise != null) b.set_member_name ("sunrise").add_string_value (Format.hour (d.sunrise));
            if (d.sunset != null) b.set_member_name ("sunset").add_string_value (Format.hour (d.sunset));
        }

        private static async void now (WeatherApp app, Json.Object args, owned Singularity.AppIntentReply reply) {
            app.hold ();
            try {
                var place = yield resolve (app, text (args, "place"));
                var f = yield fetch (app, place);
                var u = units (app);
                var c = Conditions.describe (f.code, f.is_day);
                var b = new Json.Builder ();
                b.begin_object ();
                place_members (b, place, f);
                b.set_member_name ("time").add_string_value (f.current_time.format_iso8601 ());
                b.set_member_name ("condition").add_string_value (c.label);
                b.set_member_name ("temperature").add_double_value (Math.round (f.temperature));
                b.set_member_name ("feels_like").add_double_value (Math.round (f.feels_like));
                b.set_member_name ("temperature_unit").add_string_value (u.temperature_symbol ());
                b.set_member_name ("humidity").add_int_value (f.humidity);
                b.set_member_name ("wind").add_double_value (Math.round (f.wind_speed));
                b.set_member_name ("wind_gusts").add_double_value (Math.round (f.wind_gusts));
                b.set_member_name ("wind_from").add_string_value (Conditions.compass (f.wind_direction));
                b.set_member_name ("speed_unit").add_string_value (u.speed_symbol ());
                b.set_member_name ("precipitation").add_double_value (tenth (f.precipitation));
                b.set_member_name ("precipitation_unit").add_string_value (u.precipitation_symbol ());
                b.set_member_name ("pressure").add_double_value (Math.round (f.pressure));
                if (f.uv >= 0) b.set_member_name ("uv").add_string_value ("%.0f %s".printf (f.uv, Conditions.uv_level (f.uv)));
                var today = f.today ();
                if (today != null) {
                    b.set_member_name ("today").begin_object ();
                    day_members (b, today);
                    b.end_object ();
                }
                b.end_object ();
                reply (b.get_root (), null);
            } catch (Error e) {
                reply (null, e);
            } finally {
                app.release ();
            }
        }

        private static async void forecast (WeatherApp app, Json.Object args, owned Singularity.AppIntentReply reply) {
            app.hold ();
            try {
                var place = yield resolve (app, text (args, "place"));
                var f = yield fetch (app, place);
                int64 days = args.has_member ("days") ? args.get_int_member ("days").clamp (1, 16) : 7;
                int64 hours = args.has_member ("hours") ? args.get_int_member ("hours").clamp (0, 48) : 0;
                var b = new Json.Builder ();
                b.begin_object ();
                place_members (b, place, f);
                b.set_member_name ("temperature_unit").add_string_value (units (app).temperature_symbol ());
                b.set_member_name ("days").begin_array ();
                int n = 0;
                foreach (var d in f.days) {
                    if (d == null || n++ == days) break;
                    b.begin_object ();
                    day_members (b, d);
                    b.end_object ();
                }
                b.end_array ();
                if (hours > 0) {
                    b.set_member_name ("hours").begin_array ();
                    int64 from = f.current_time.to_unix () - 3600;
                    int m = 0;
                    foreach (var h in f.hours) {
                        if (h == null || h.time.to_unix () < from) continue;
                        if (m++ == hours) break;
                        b.begin_object ();
                        b.set_member_name ("time").add_string_value (h.time.format_iso8601 ());
                        b.set_member_name ("condition").add_string_value (Conditions.describe (h.code, h.day).label);
                        b.set_member_name ("temperature").add_double_value (Math.round (h.temperature));
                        b.set_member_name ("precipitation_chance").add_int_value (h.precipitation_probability);
                        b.end_object ();
                    }
                    b.end_array ();
                }
                b.end_object ();
                reply (b.get_root (), null);
            } catch (Error e) {
                reply (null, e);
            } finally {
                app.release ();
            }
        }

        private static async void add (WeatherApp app, Json.Object args, owned Singularity.AppIntentReply reply) {
            app.hold ();
            try {
                string query = text (args, "place");
                if (query == "") throw new IOError.INVALID_ARGUMENT ("give a place");
                var found = yield app.service.search (query);
                if (found.size == 0) throw new IOError.NOT_FOUND ("no place matches %s", query);
                var place = found[0];
                var window = open_window (app);
                if (window != null) {
                    window.add_place (place);
                } else {
                    var saved = Snapshot.places (app.settings);
                    bool known = false;
                    foreach (var p in saved) if (p.id == place.id) known = true;
                    if (!known) saved.add (place);
                    var builder = new VariantBuilder (new VariantType ("a(sssdd)"));
                    foreach (var p in saved) builder.add ("(sssdd)", p.name, p.region, p.country, p.latitude, p.longitude);
                    app.settings.set_value ("places", builder.end ());
                    app.settings.set_string ("selected", place.id);
                }
                bool saved_now = false;
                foreach (var p in Snapshot.places (app.settings)) if (p.id == place.id) saved_now = true;
                if (!saved_now) throw new IOError.FAILED ("the place was not saved");
                var b = new Json.Builder ();
                b.begin_object ();
                place_members (b, place, null);
                b.set_member_name ("saved").add_boolean_value (true);
                b.end_object ();
                reply (b.get_root (), null);
            } catch (Error e) {
                reply (null, e);
            } finally {
                app.release ();
            }
        }

        private static async void show (WeatherApp app, Json.Object args, owned Singularity.AppIntentReply reply) {
            try {
                var place = yield resolve (app, text (args, "place"));
                bool known = false;
                foreach (var p in Snapshot.places (app.settings)) if (p.id == place.id) known = true;
                if (known) {
                    app.activate ();
                    app.activate_action ("show-place", new Variant.string (place.id));
                } else {
                    app.open_place (place);
                }
                var b = new Json.Builder ();
                b.begin_object ();
                place_members (b, place, null);
                b.set_member_name ("saved").add_boolean_value (true);
                b.end_object ();
                reply (b.get_root (), null);
            } catch (Error e) {
                reply (null, e);
            }
        }

        internal static void install (WeatherApp app) {
            var agent = app.agent;
            agent.add_intent ("weather_places", "List the places saved in Weather, with the one shown first.",
                "{\"type\":\"object\",\"properties\":{}}", Singularity.AppIntentRisk.READ, (args) => {
                    string selected = app.settings.get_string ("selected");
                    var list = new Json.Array ();
                    foreach (var p in Snapshot.places (app.settings)) {
                        var o = new Json.Object ();
                        o.set_string_member ("id", p.id);
                        o.set_string_member ("place", p.name);
                        o.set_string_member ("region", p.subtitle ());
                        o.set_boolean_member ("selected", p.id == selected);
                        list.add_object_element (o);
                    }
                    var node = new Json.Node (Json.NodeType.ARRAY);
                    node.set_array (list);
                    return node;
                });
            agent.add_async_intent ("weather_now", "The weather right now and today's range for a place: a saved place, any city, or the selected place when none is given.",
                PLACE, Singularity.AppIntentRisk.READ, (args, reply) => {
                    now.begin (app, args, (owned) reply);
                });
            agent.add_async_intent ("weather_forecast", "The forecast for a place, day by day for up to 16 days (7 by default), and hour by hour for up to 48 hours when hours is given.",
                "{\"type\":\"object\",\"properties\":{\"place\":{\"type\":\"string\"},\"days\":{\"type\":\"integer\"},\"hours\":{\"type\":\"integer\"}}}",
                Singularity.AppIntentRisk.READ, (args, reply) => {
                    forecast.begin (app, args, (owned) reply);
                });
            agent.add_async_intent ("weather_add_place", "Save a place in Weather by name and show it first.",
                "{\"type\":\"object\",\"properties\":{\"place\":{\"type\":\"string\"}},\"required\":[\"place\"]}",
                Singularity.AppIntentRisk.UNDOABLE, (args, reply) => {
                    add.begin (app, args, (owned) reply);
                });
            agent.add_async_intent ("weather_show", "Open the Weather window on a place; a place that is not saved yet gets saved.",
                PLACE, Singularity.AppIntentRisk.UNDOABLE, (args, reply) => {
                    show.begin (app, args, (owned) reply);
                });
        }
    }
}
