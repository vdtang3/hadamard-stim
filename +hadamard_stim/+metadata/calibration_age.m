function age = calibration_age(when, now_utc)
%CALIBRATION_AGE When a calibration or check was taken, in words.
%
%   age = hadamard_stim.metadata.calibration_age(when)
%   age = hadamard_stim.metadata.calibration_age(when, now_utc)
%
%   when is a datetime, ISO text ("2026-10-19T14:02:11Z" or "2026-10-19"),
%   or empty / NaT when the time was not recorded.
%
%   age.taken_utc  ISO time, "" when not recorded
%   age.taken      "Oct 19, 2026", "" when not recorded
%   age.ago        "today", "yesterday", "9 days ago", "3 weeks ago",
%                  "4 months ago", "2 years ago", or "date not recorded"
%   age.age_days   whole days, [] when not recorded
%   age.today      taken on now_utc's day
%   age.text       "Taken today (Oct 28, 2026)", "Taken Oct 19, 2026
%                  (9 days ago)", or "Date not recorded"
%
%   Age is text only: it never changes a readiness status (a compatible
%   calibration passes whether it was taken today or a year ago), and it
%   is never a warning or a blocker (docs/notebook.md, 2026-10-28). A
%   calibration warns because it does not fit the current settings,
%   whatever its age.
arguments
    when = []
    now_utc (1, 1) datetime = datetime("now", "TimeZone", "UTC")
end
age = struct("taken_utc", "", "taken", "", "ago", "date not recorded", ...
    "age_days", [], "today", false, "text", "Date not recorded");
when = parse(when);
if isnat(when)
    return
end
if isempty(now_utc.TimeZone)
    now_utc.TimeZone = "UTC";
end
d = floor(days(dateshift(now_utc, "start", "day") - dateshift(when, "start", "day")));
d = max(d, 0);
age.taken_utc = string(datetime(when, "Format", "yyyy-MM-dd'T'HH:mm:ss'Z'"));
age.taken = string(datetime(when, "Format", "MMM d, yyyy"));
age.age_days = d;
age.today = d == 0;
if d == 0
    age.ago = "today";
elseif d == 1
    age.ago = "yesterday";
elseif d < 14
    age.ago = sprintf("%d days ago", d);
elseif d < 60
    age.ago = sprintf("%d weeks ago", floor(d / 7));
elseif d < 730
    age.ago = sprintf("%d months ago", round(d / 30.44));
else
    age.ago = sprintf("%d years ago", floor(d / 365.25));
end
age.ago = string(age.ago);
if age.today
    age.text = "Taken today (" + age.taken + ")";
else
    age.text = "Taken " + age.taken + " (" + age.ago + ")";
end
end

function when = parse(value)
when = NaT("TimeZone", "UTC");
if isempty(value)
    return
end
if isdatetime(value)
    when = value;
    if isempty(when.TimeZone)
        when.TimeZone = "UTC";
    end
    return
end
value = string(value);
if ~isscalar(value) || strlength(value) == 0
    return
end
for format = ["yyyy-MM-dd'T'HH:mm:ss'Z'" "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'" "yyyy-MM-dd"]
    try
        when = datetime(value, "InputFormat", format, "TimeZone", "UTC");
        return
    catch
    end
end
end
