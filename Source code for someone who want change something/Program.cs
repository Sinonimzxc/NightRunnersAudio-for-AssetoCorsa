using System.Diagnostics;
using System.Globalization;
using System.Net;
using System.Text;
using NAudio.CoreAudioApi;

const int Port = 8765;
float currentVolume = 1.0f;
string currentSource = "yandex";
string lastSession = "not found";
uint cachedPid = 0;

Console.Title = "Night Runners Audio Bridge v0.4";
Console.WriteLine("Night Runners Audio Bridge v0.4");
Console.WriteLine($"Listening: http://127.0.0.1:{Port}/");
Console.WriteLine();

using var listener = new HttpListener();
listener.Prefixes.Add($"http://127.0.0.1:{Port}/");

try { listener.Start(); }
catch (HttpListenerException ex)
{
    Console.WriteLine("Не удалось запустить HTTP-сервер.");
    Console.WriteLine(ex.Message);
    Console.WriteLine("Попробуй запустить Bridge от имени администратора.");
    Console.ReadKey();
    return;
}

while (true)
{
    var context = await listener.GetContextAsync();

    try
    {
        string path = context.Request.Url?.AbsolutePath ?? "/";
        var query = context.Request.QueryString;

        if (path.Equals("/volume", StringComparison.OrdinalIgnoreCase))
        {
            if (!float.TryParse(query["value"], NumberStyles.Float,
                CultureInfo.InvariantCulture, out float value))
            {
                await WriteResponse(context, 400, "Invalid volume value");
                continue;
            }

            currentVolume = Math.Clamp(value, 0f, 1f);
            string source = string.IsNullOrWhiteSpace(query["source"])
                ? currentSource
                : query["source"]!.Trim().ToLowerInvariant();

            if (!source.Equals(currentSource, StringComparison.OrdinalIgnoreCase))
            {
                currentSource = source;
                cachedPid = 0;
                lastSession = "switching...";

                Console.WriteLine(
                    $"Source switched -> {currentSource}");
            }

            var result = SetMusicVolumeWithRetry(
            currentSource,
            currentVolume,
            cachedPid,
            10,
            100);

            if (result.Found)
            {
                cachedPid = result.ProcessId;
                lastSession = result.SessionName;

                await WriteResponse(
                    context,
                    200,
                    $"OK source={currentSource} " +
                    $"volume={currentVolume:0.000} " +
                    $"session={lastSession}");
            }
            else
            {
                cachedPid = 0;
                lastSession = "not found";

                await WriteResponse(
                    context,
                    404,
                    $"Audio session not found: source={currentSource}");
            }
        }
        else if (path.Equals("/status", StringComparison.OrdinalIgnoreCase))
        {
            await WriteResponse(context, 200,
                $"source={currentSource} volume={currentVolume:0.000} pid={cachedPid} session={lastSession}");
        }
        else if (path.Equals("/scan", StringComparison.OrdinalIgnoreCase))
        {
            await WriteResponse(context, 200, string.Join(Environment.NewLine, ScanSessions()));
        }
        else
        {
            await WriteResponse(context, 200, "Night Runners Audio Bridge v0.4 is running.");
        }
    }
    catch (Exception ex)
    {
        try { await WriteResponse(context, 500, ex.Message); } catch { }
    }
}

static (bool Found, uint ProcessId, string SessionName)
    SetMusicVolumeWithRetry(
        string source,
        float volume,
        uint cachedPid,
        int attempts,
        int delayMs)
{
    for (int attempt = 0; attempt < attempts; attempt++)
    {
        // Сначала пробуем ранее найденный PID
        if (cachedPid != 0)
        {
            var cachedResult = TrySetByPid(
                source,
                cachedPid,
                volume);

            if (cachedResult.Found)
                return cachedResult;
        }

        // Если старый PID не найден — ищем заново
        var result = FindAndSet(
            source,
            volume);

        if (result.Found)
            return result;

        if (attempt + 1 < attempts)
            Thread.Sleep(delayMs);
    }

    return (false, 0, "not found");
}

static (bool Found, uint ProcessId, string SessionName)
    TrySetByPid(string source, uint pid, float volume)
{
    try
    {
        using var enumerator = new MMDeviceEnumerator();
        foreach (var device in enumerator.EnumerateAudioEndPoints(DataFlow.Render, DeviceState.Active))
        {
            var sessions = device.AudioSessionManager.Sessions;
            for (int i = 0; i < sessions.Count; i++)
            {
                var session = sessions[i];
                if (session.GetProcessID != pid) continue;

                using var process = Process.GetProcessById((int)pid);
                string processName = process.ProcessName ?? "";
                string displayName = "";
                try { displayName = session.DisplayName ?? ""; } catch { }

                if (!MatchesSource(source, processName, displayName))
                    return (false, 0, "not found");

                session.SimpleAudioVolume.Volume = Math.Clamp(volume, 0f, 1f);
                session.SimpleAudioVolume.Mute = false;

                return (true, pid, $"{processName} (PID {pid})");
            }
        }
    }
    catch { }

    return (false, 0, "not found");
}

static (bool Found, uint ProcessId, string SessionName)
    FindAndSet(string source, float volume)
{
    try
    {
        using var enumerator = new MMDeviceEnumerator();
        foreach (var device in enumerator.EnumerateAudioEndPoints(DataFlow.Render, DeviceState.Active))
        {
            var sessions = device.AudioSessionManager.Sessions;
            for (int i = 0; i < sessions.Count; i++)
            {
                var session = sessions[i];
                uint pid = session.GetProcessID;
                if (pid == 0) continue;

                try
                {
                    using var process = Process.GetProcessById((int)pid);
                    string processName = process.ProcessName ?? "";
                    string displayName = "";
                    try { displayName = session.DisplayName ?? ""; } catch { }

                    if (!MatchesSource(source, processName, displayName))
                        continue;

                    session.SimpleAudioVolume.Volume = Math.Clamp(volume, 0f, 1f);
                    session.SimpleAudioVolume.Mute = false;

                    return (true, pid, $"{processName} (PID {pid})");
                }
                catch { }
            }
        }
    }
    catch { }

    return (false, 0, "not found");
}

static List<string> ScanSessions()
{
    var result = new List<string>();
    try
    {
        using var enumerator = new MMDeviceEnumerator();
        foreach (var device in enumerator.EnumerateAudioEndPoints(DataFlow.Render, DeviceState.Active))
        {
            var sessions = device.AudioSessionManager.Sessions;
            for (int i = 0; i < sessions.Count; i++)
            {
                var session = sessions[i];
                uint pid = session.GetProcessID;
                if (pid == 0) continue;

                try
                {
                    using var process = Process.GetProcessById((int)pid);
                    string display = "";
                    try { display = session.DisplayName ?? ""; } catch { }
                    result.Add($"{process.ProcessName} | PID={pid} | Display=\"{display}\"");
                }
                catch { }
            }
        }
    }
    catch (Exception ex) { result.Add($"SCAN ERROR: {ex.Message}"); }

    return result;
}

static bool MatchesSource(string source, string processName, string displayName)
{
    string p = processName.ToLowerInvariant();
    string d = displayName.ToLowerInvariant();

    return source switch
    {
        "yandex" => p.Contains("yandex") || p.Contains("yandexmusic") ||
                    p.Contains("ymusic") || p.Contains("яндекс") ||
                    d.Contains("yandex") || d.Contains("яндекс") || d.Contains("музыка"),

        "spotify" => p.Contains("spotify") || d.Contains("spotify"),
        "chrome" => p.Contains("chrome") || d.Contains("chrome"),
        "edge" => p.Contains("msedge") || d.Contains("edge"),
        "firefox" => p.Contains("firefox") || d.Contains("firefox"),
        "wmp" => p.Contains("wmplayer") || p.Contains("windowsmedia") ||
                 p.Contains("music.ui") || d.Contains("windows media") ||
                 d.Contains("media player"),
        _ => false
    };
}

static async Task WriteResponse(HttpListenerContext context, int status, string text)
{
    byte[] data = Encoding.UTF8.GetBytes(text);
    context.Response.StatusCode = status;
    context.Response.ContentType = "text/plain; charset=utf-8";
    context.Response.ContentLength64 = data.Length;
    await context.Response.OutputStream.WriteAsync(data);
    context.Response.Close();
}
