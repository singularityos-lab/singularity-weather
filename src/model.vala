namespace Singularity.Apps.Weather {

    public enum Units {
        METRIC,
        IMPERIAL;

        public static Units from_setting (string value) {
            if (value == "imperial") return IMPERIAL;
            if (value == "metric") return METRIC;
            string? locale = Environment.get_variable ("LC_MEASUREMENT") ?? Environment.get_variable ("LC_ALL") ?? Environment.get_variable ("LANG");
            if (locale != null) {
                foreach (string region in new string[] { "_US", "_LR", "_MM" }) {
                    if (locale.contains (region)) return IMPERIAL;
                }
            }
            return METRIC;
        }

        public string temperature_symbol () {
            return this == IMPERIAL ? "°F" : "°C";
        }

        public string speed_symbol () {
            return this == IMPERIAL ? "mph" : "km/h";
        }

        public string precipitation_symbol () {
            return this == IMPERIAL ? "in" : "mm";
        }
    }

    public class Place : Object {
        public string id;
        public string name;
        public string region;
        public string country;
        public double latitude;
        public double longitude;
        public int64 population = 0;

        public Place (string name, string region, string country, double latitude, double longitude) {
            this.name = name;
            this.region = region;
            this.country = country;
            this.latitude = latitude;
            this.longitude = longitude;
            char[] a = new char[double.DTOSTR_BUF_SIZE];
            char[] b = new char[double.DTOSTR_BUF_SIZE];
            id = "%s,%s".printf (latitude.format (a, "%.4f"), longitude.format (b, "%.4f"));
        }

        public string subtitle () {
            if (region != "" && country != "" && region != name) return "%s, %s".printf (region, country);
            if (country != "") return country;
            return region;
        }

        public string coordinates () {
            return "%.2f°%s, %.2f°%s".printf (latitude.abs (), latitude >= 0 ? "N" : "S", longitude.abs (), longitude >= 0 ? "E" : "W");
        }

        public static Place? from_coordinates (string text) {
            try {
                var re = new Regex ("^\\s*(-?\\d{1,2}(?:[.,]\\d+)?)\\s*[,; ]\\s*(-?\\d{1,3}(?:[.,]\\d+)?)\\s*$");
                MatchInfo m;
                if (!re.match (text, 0, out m)) return null;
                double lat = double.parse (m.fetch (1).replace (",", "."));
                double lon = double.parse (m.fetch (2).replace (",", "."));
                if (lat < -90 || lat > 90 || lon < -180 || lon > 180) return null;
                return new Place (_("Custom Location"), "", "", lat, lon);
            } catch (RegexError e) {
                return null;
            }
        }
    }

    public struct Condition {
        public string label;
        public string icon;
        public string sky;
    }

    public class Conditions {
        public static Condition describe (int code, bool day) {
            Condition c = Condition ();
            switch (code) {
                case 0:
                    c.label = day ? _("Clear Sky") : _("Clear Night");
                    c.icon = day ? "weather-clear" : "weather-clear-night";
                    c.sky = day ? "clear" : "night";
                    break;
                case 1:
                    c.label = _("Mainly Clear");
                    c.icon = day ? "weather-few-clouds" : "weather-few-clouds-night";
                    c.sky = day ? "clear" : "night";
                    break;
                case 2:
                    c.label = _("Partly Cloudy");
                    c.icon = day ? "weather-few-clouds" : "weather-few-clouds-night";
                    c.sky = day ? "cloudy" : "night";
                    break;
                case 3:
                    c.label = _("Overcast");
                    c.icon = "weather-overcast";
                    c.sky = day ? "overcast" : "night-cloudy";
                    break;
                case 45:
                case 48:
                    c.label = _("Fog");
                    c.icon = "weather-fog";
                    c.sky = day ? "fog" : "night-cloudy";
                    break;
                case 51:
                case 53:
                case 55:
                    c.label = _("Drizzle");
                    c.icon = "weather-showers-scattered";
                    c.sky = day ? "rain" : "night-cloudy";
                    break;
                case 56:
                case 57:
                    c.label = _("Freezing Drizzle");
                    c.icon = "weather-showers-scattered";
                    c.sky = day ? "rain" : "night-cloudy";
                    break;
                case 61:
                    c.label = _("Light Rain");
                    c.icon = "weather-showers-scattered";
                    c.sky = day ? "rain" : "night-cloudy";
                    break;
                case 63:
                    c.label = _("Rain");
                    c.icon = "weather-showers";
                    c.sky = day ? "rain" : "night-cloudy";
                    break;
                case 65:
                    c.label = _("Heavy Rain");
                    c.icon = "weather-showers";
                    c.sky = day ? "rain" : "night-cloudy";
                    break;
                case 66:
                case 67:
                    c.label = _("Freezing Rain");
                    c.icon = "weather-showers";
                    c.sky = day ? "rain" : "night-cloudy";
                    break;
                case 71:
                    c.label = _("Light Snow");
                    c.icon = "weather-snow";
                    c.sky = day ? "snow" : "night-cloudy";
                    break;
                case 73:
                    c.label = _("Snow");
                    c.icon = "weather-snow";
                    c.sky = day ? "snow" : "night-cloudy";
                    break;
                case 75:
                    c.label = _("Heavy Snow");
                    c.icon = "weather-snow";
                    c.sky = day ? "snow" : "night-cloudy";
                    break;
                case 77:
                    c.label = _("Snow Grains");
                    c.icon = "weather-snow";
                    c.sky = day ? "snow" : "night-cloudy";
                    break;
                case 80:
                    c.label = _("Light Showers");
                    c.icon = "weather-showers-scattered";
                    c.sky = day ? "rain" : "night-cloudy";
                    break;
                case 81:
                    c.label = _("Showers");
                    c.icon = "weather-showers";
                    c.sky = day ? "rain" : "night-cloudy";
                    break;
                case 82:
                    c.label = _("Violent Showers");
                    c.icon = "weather-showers";
                    c.sky = day ? "storm" : "night-cloudy";
                    break;
                case 85:
                case 86:
                    c.label = _("Snow Showers");
                    c.icon = "weather-snow";
                    c.sky = day ? "snow" : "night-cloudy";
                    break;
                case 95:
                    c.label = _("Thunderstorm");
                    c.icon = "weather-storm";
                    c.sky = "storm";
                    break;
                case 96:
                case 99:
                    c.label = _("Thunderstorm with Hail");
                    c.icon = "weather-storm";
                    c.sky = "storm";
                    break;
                default:
                    c.label = _("Unknown");
                    c.icon = "weather-severe-alert";
                    c.sky = day ? "overcast" : "night";
                    break;
            }
            return c;
        }

        public static string compass (double degrees) {
            string[] names = { _("N"), _("NE"), _("E"), _("SE"), _("S"), _("SW"), _("W"), _("NW") };
            int index = (int) Math.round (((degrees % 360) + 360) % 360 / 45.0) % 8;
            return names[index];
        }

        public static string uv_level (double uv) {
            if (uv < 3) return _("Low");
            if (uv < 6) return _("Moderate");
            if (uv < 8) return _("High");
            if (uv < 11) return _("Very High");
            return _("Extreme");
        }
    }

    public struct Hour {
        public DateTime time;
        public double temperature;
        public int precipitation_probability;
        public int code;
        public bool day;
    }

    public struct Day {
        public DateTime date;
        public int code;
        public double high;
        public double low;
        public DateTime? sunrise;
        public DateTime? sunset;
        public double daylight_seconds;
        public double uv_max;
        public double precipitation;
        public int precipitation_probability;
    }

    public class Forecast : Object {
        public TimeZone zone;
        public string timezone_name = "";
        public DateTime current_time;
        public double temperature;
        public double feels_like;
        public int humidity;
        public bool is_day = true;
        public int code;
        public double wind_speed;
        public double wind_gusts;
        public double wind_direction;
        public double pressure;
        public double precipitation;
        public double visibility = -1;
        public double uv = -1;
        public Gee.ArrayList<Hour?> hours = new Gee.ArrayList<Hour?> ();
        public Gee.ArrayList<Day?> days = new Gee.ArrayList<Day?> ();
        public int64 fetched_at;

        private static DateTime? parse_time (TimeZone zone, string text) {
            string value = text.length == 10 ? text + "T00:00" : text;
            return new DateTime.from_iso8601 (value + ":00", zone);
        }

        private static double num (Json.Array? array, uint index, double fallback = 0) {
            if (array == null || index >= array.get_length ()) return fallback;
            var node = array.get_element (index);
            if (node.is_null ()) return fallback;
            return node.get_double ();
        }

        private static double member (Json.Object obj, string name, double fallback = 0) {
            if (!obj.has_member (name)) return fallback;
            var node = obj.get_member (name);
            if (node.is_null ()) return fallback;
            return node.get_double ();
        }

        public static Forecast parse (string text) throws Error {
            var parser = new Json.Parser ();
            parser.load_from_data (text);
            var root = parser.get_root ();
            if (root == null || root.get_node_type () != Json.NodeType.OBJECT) throw new IOError.INVALID_DATA ("Unexpected answer from the weather service");
            var obj = root.get_object ();
            if (obj.has_member ("error") && obj.get_boolean_member ("error")) {
                throw new IOError.FAILED ("%s", obj.has_member ("reason") ? obj.get_string_member ("reason") : "Weather service error");
            }
            var f = new Forecast ();
            int offset = obj.has_member ("utc_offset_seconds") ? (int) obj.get_int_member ("utc_offset_seconds") : 0;
            f.timezone_name = obj.has_member ("timezone") ? obj.get_string_member ("timezone") : "";
            try {
                f.zone = f.timezone_name != "" && f.timezone_name != "GMT" ? new TimeZone.identifier (f.timezone_name) : new TimeZone.offset (offset);
            } catch (Error e) {
                f.zone = new TimeZone.offset (offset);
            }
            f.fetched_at = obj.has_member ("fetched_at") ? obj.get_int_member ("fetched_at") : get_real_time () / 1000000;

            var current = obj.get_object_member ("current");
            f.current_time = parse_time (f.zone, current.get_string_member ("time")) ?? new DateTime.now (f.zone);
            f.temperature = member (current, "temperature_2m");
            f.feels_like = member (current, "apparent_temperature", f.temperature);
            f.humidity = (int) member (current, "relative_humidity_2m");
            f.is_day = member (current, "is_day", 1) != 0;
            f.code = (int) member (current, "weather_code");
            f.wind_speed = member (current, "wind_speed_10m");
            f.wind_gusts = member (current, "wind_gusts_10m");
            f.wind_direction = member (current, "wind_direction_10m");
            f.pressure = member (current, "pressure_msl");
            f.precipitation = member (current, "precipitation");

            var hourly = obj.get_object_member ("hourly");
            var times = hourly.get_array_member ("time");
            var temps = hourly.get_array_member ("temperature_2m");
            var probs = hourly.has_member ("precipitation_probability") ? hourly.get_array_member ("precipitation_probability") : null;
            var codes = hourly.get_array_member ("weather_code");
            var days_flags = hourly.has_member ("is_day") ? hourly.get_array_member ("is_day") : null;
            var visibility = hourly.has_member ("visibility") ? hourly.get_array_member ("visibility") : null;
            var uv = hourly.has_member ("uv_index") ? hourly.get_array_member ("uv_index") : null;
            var now_hour = new DateTime (f.zone, f.current_time.get_year (), f.current_time.get_month (), f.current_time.get_day_of_month (), f.current_time.get_hour (), 0, 0);
            for (uint i = 0; i < times.get_length (); i++) {
                var t = parse_time (f.zone, times.get_string_element (i));
                if (t == null) continue;
                if (t.compare (now_hour) == 0) {
                    f.visibility = num (visibility, i, -1);
                    f.uv = num (uv, i, -1);
                }
                if (t.compare (now_hour) < 0) continue;
                Hour h = Hour ();
                h.time = t;
                h.temperature = num (temps, i);
                h.precipitation_probability = (int) num (probs, i, 0);
                h.code = (int) num (codes, i);
                h.day = num (days_flags, i, 1) != 0;
                f.hours.add (h);
            }

            var daily = obj.get_object_member ("daily");
            var dtimes = daily.get_array_member ("time");
            var dcodes = daily.get_array_member ("weather_code");
            var highs = daily.get_array_member ("temperature_2m_max");
            var lows = daily.get_array_member ("temperature_2m_min");
            var sunrises = daily.has_member ("sunrise") ? daily.get_array_member ("sunrise") : null;
            var sunsets = daily.has_member ("sunset") ? daily.get_array_member ("sunset") : null;
            var daylight = daily.has_member ("daylight_duration") ? daily.get_array_member ("daylight_duration") : null;
            var uv_max = daily.has_member ("uv_index_max") ? daily.get_array_member ("uv_index_max") : null;
            var psum = daily.has_member ("precipitation_sum") ? daily.get_array_member ("precipitation_sum") : null;
            var pmax = daily.has_member ("precipitation_probability_max") ? daily.get_array_member ("precipitation_probability_max") : null;
            for (uint i = 0; i < dtimes.get_length (); i++) {
                Day d = Day ();
                d.date = parse_time (f.zone, dtimes.get_string_element (i));
                if (d.date == null) continue;
                d.code = (int) num (dcodes, i);
                d.high = num (highs, i);
                d.low = num (lows, i);
                if (sunrises != null && !sunrises.get_element (i).is_null ()) d.sunrise = parse_time (f.zone, sunrises.get_string_element (i));
                if (sunsets != null && !sunsets.get_element (i).is_null ()) d.sunset = parse_time (f.zone, sunsets.get_string_element (i));
                d.daylight_seconds = num (daylight, i, 0);
                d.uv_max = num (uv_max, i, 0);
                d.precipitation = num (psum, i, 0);
                d.precipitation_probability = (int) num (pmax, i, 0);
                f.days.add (d);
            }
            if (f.uv < 0 && f.days.size > 0) f.uv = f.days[0].uv_max;
            return f;
        }

        public Day? today () {
            return days.size > 0 ? days[0] : null;
        }

        public static double sun_progress (DateTime now, DateTime? sunrise, DateTime? sunset) {
            if (sunrise == null || sunset == null) return -1;
            double total = sunset.difference (sunrise);
            if (total <= 0) return -1;
            double elapsed = now.difference (sunrise);
            if (elapsed < 0) return -1;
            if (elapsed > total) return 2;
            return elapsed / total;
        }
    }

    public class Format {
        public static string temperature (double value) {
            return "%d°".printf ((int) Math.round (value));
        }

        public static string duration (double seconds) {
            int minutes = (int) Math.round (seconds / 60.0);
            return _("%dh %02dm").printf (minutes / 60, minutes % 60);
        }

        public static string hour (DateTime time) {
            return time.format ("%H:%M");
        }

        public static string weekday (DateTime date, DateTime today) {
            int diff = (int) Math.round (date.difference (new DateTime (date.get_timezone (), today.get_year (), today.get_month (), today.get_day_of_month (), 0, 0, 0)) / (double) TimeSpan.DAY);
            if (diff == 0) return _("Today");
            if (diff == 1) return _("Tomorrow");
            return date.format ("%A");
        }
    }
}
