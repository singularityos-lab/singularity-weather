namespace Singularity.Apps.Weather {

    public class WeatherSearch : Singularity.SearchProviderService {
        private const uint SETTLE_MS = 400;

        private weak WeatherApp app;
        private uint generation;
        private Gee.HashMap<string, Gee.List<Place>> lookups = new Gee.HashMap<string, Gee.List<Place>> ();
        private Gee.HashMap<string, Forecast> now = new Gee.HashMap<string, Forecast> ();
        private WeatherService? service;

        public WeatherSearch (WeatherApp app) {
            this.app = app;
        }

        public static string? query (string[] terms) {
            if (terms.length < 2) return null;
            string first = terms[0].casefold ();
            string[] prefixes = { "weather", "meteo", _("weather").casefold () };
            bool matched = false;
            foreach (unowned string p in prefixes) if (first == p) matched = true;
            if (!matched) return null;
            string rest = string.joinv (" ", terms[1:terms.length]).strip ();
            return rest.char_count () >= 2 ? rest : null;
        }

        public static string encode (Place place) {
            char[] a = new char[double.DTOSTR_BUF_SIZE];
            char[] b = new char[double.DTOSTR_BUF_SIZE];
            return string.join ("\n", place.latitude.format (a, "%.5f"), place.longitude.format (b, "%.5f"), place.name, place.region, place.country);
        }

        public static Place? decode (string id) {
            string[] parts = id.split ("\n");
            if (parts.length != 5) return null;
            return new Place (parts[2], parts[3], parts[4], double.parse (parts[0]), double.parse (parts[1]));
        }

        private WeatherService get_service () {
            if (service == null) service = new WeatherService ();
            return service;
        }

        private GLib.Settings settings () {
            return new GLib.Settings ("dev.sinty.weather");
        }

        private async void pause (uint ms) {
            Timeout.add (ms, pause.callback);
            yield;
        }

        public override async string[] get_initial_results (string[] terms, Cancellable? cancellable) throws Error {
            string? text = query (terms);
            if (text == null) return {};
            string key = text.casefold ();
            uint gen = ++generation;
            if (!lookups.has_key (key)) {
                yield pause (SETTLE_MS);
                if (gen != generation) return {};
                var found = new Gee.ArrayList<Place> ();
                found.add_all (yield get_service ().search (text));
                string folded = text.casefold ();
                found.sort ((a, b) => {
                    int64 wa = int64.max (a.population, 1) * (a.name.casefold () == folded ? 10 : 1);
                    int64 wb = int64.max (b.population, 1) * (b.name.casefold () == folded ? 10 : 1);
                    return wa > wb ? -1 : (wa < wb ? 1 : 0);
                });
                lookups[key] = found;
                if (gen != generation) return {};
            }
            string[] ids = {};
            foreach (var place in lookups[key]) {
                ids += encode (place);
                if (ids.length == 3) break;
            }
            return ids;
        }

        public override async Singularity.SearchResultMeta[] get_result_metas (string[] ids, Cancellable? cancellable) throws Error {
            var units = Units.from_setting (settings ().get_string ("units"));
            int pending = 0;
            foreach (string id in ids) {
                if (now.has_key (id) || decode (id) == null) continue;
                pending++;
                fetch.begin (id, units, (o, r) => {
                    fetch.end (r);
                    pending--;
                    if (pending == 0) get_result_metas.callback ();
                });
            }
            if (pending > 0) {
                uint timeout = Timeout.add (1800, () => {
                    if (pending > 0) {
                        pending = 0;
                        get_result_metas.callback ();
                    }
                    return Source.REMOVE;
                });
                yield;
                if (pending == 0) Source.remove (timeout);
            }
            Singularity.SearchResultMeta[] metas = {};
            foreach (string id in ids) {
                var place = decode (id);
                if (place == null) continue;
                string where = place.subtitle ();
                var f = now[id];
                Singularity.SearchResultMeta meta;
                if (f != null) {
                    var cond = Conditions.describe (f.code, f.is_day);
                    string temp = Format.temperature (f.temperature) + (units == Units.IMPERIAL ? "F" : "C");
                    meta = new Singularity.SearchResultMeta (id, "%s, %s".printf (temp, cond.label));
                    string desc = where != "" ? "%s, %s".printf (place.name, where) : place.name;
                    var today = f.today ();
                    if (today != null) desc = _("%s. High %s, low %s").printf (desc, Format.temperature (today.high), Format.temperature (today.low));
                    meta.description = desc;
                    meta.icon = new ThemedIcon (cond.icon);
                } else {
                    meta = new Singularity.SearchResultMeta (id, _("Weather in %s").printf (place.name));
                    meta.description = where != "" ? where : place.coordinates ();
                    meta.icon = new ThemedIcon ("weather-few-clouds");
                }
                metas += meta;
            }
            return metas;
        }

        private async void fetch (string id, Units units) {
            var place = decode (id);
            try {
                now[id] = yield get_service ().current (place, units);
            } catch (Error e) {
                debug ("Weather search: %s", e.message);
            }
        }

        public override async Singularity.SearchActivationReply? activate_result (string id, string[] terms, uint32 timestamp) throws Error {
            var place = decode (id);
            if (place != null) app.open_place (place);
            return null;
        }

        public override void launch_search (string[] terms, uint32 timestamp) {
            app.activate ();
            app.activate_action ("add-place", null);
        }
    }
}
