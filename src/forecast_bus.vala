namespace Singularity.Apps.Weather {

    [DBus (name = "dev.sinty.Weather1")]
    public class ForecastBus : Object {
        private unowned WeatherApp app;
        private WeatherService? own_service = null;

        public ForecastBus (WeatherApp app) {
            this.app = app;
        }

        public async void forecast_at (string location, int64 unix_time, out string label, out string icon, out double temperature,
                                       out int precipitation, out string place) throws Error {
            app.hold ();
            try {
                var service = app.service;
                if (service == null) {
                    if (own_service == null) own_service = new WeatherService ();
                    service = own_service;
                }
                var places = yield service.search (location);
                if (places.size == 0) throw new IOError.NOT_FOUND ("No place matches %s", location);
                var p = places[0];
                var units = app.settings != null ? Units.from_setting (app.settings.get_string ("units")) : Units.from_setting (new GLib.Settings ("dev.sinty.weather").get_string ("units"));
                var f = yield service.forecast (p, units);
                var when = new DateTime.from_unix_utc (unix_time);
                Hour? best = null;
                int64 gap = int64.MAX;
                foreach (var h in f.hours) {
                    if (h == null) continue;
                    int64 d = (h.time.to_unix () - unix_time).abs ();
                    if (d < gap) {
                        gap = d;
                        best = h;
                    }
                }
                if (best == null || gap > 3 * 3600) throw new IOError.NOT_FOUND ("No forecast for %s", when.format_iso8601 ());
                var c = Conditions.describe (best.code, best.day);
                label = c.label;
                icon = c.icon;
                temperature = best.temperature;
                precipitation = best.precipitation_probability;
                place = p.name;
            } finally {
                app.release ();
            }
        }
    }
}
