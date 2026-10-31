pragma Singleton

import QtQuick
import Quickshell
import Caelestia
import Caelestia.Config
import Caelestia.I18n
import qs.services

Singleton {
    id: root

    property bool stopwatchRunning: false
    property real stopwatchElapsed: 0

    property bool countdownRunning: false
    property int countdownDuration: 5 * 60 * 1000
    property real countdownRemaining: countdownDuration

    property real _stopwatchStartedAt: 0
    property real _stopwatchBase: 0
    property real _countdownEndsAt: 0

    // Alarm
    property bool alarmRinging: false
    property int _alarmPlays: 0

    readonly property bool alarmEnabled: alarmProps.enabled
    readonly property int alarmHour: alarmProps.hour
    readonly property int alarmMinute: alarmProps.minute
    readonly property string alarmText: pad(alarmProps.hour) + ":" + pad(alarmProps.minute)
    // Reflects snoozes, which move nextMs without changing the saved hour/minute.
    readonly property string alarmNextText: {
        if (alarmProps.nextMs <= 0)
            return alarmText;
        const next = new Date(alarmProps.nextMs);
        return pad(next.getHours()) + ":" + pad(next.getMinutes());
    }
    readonly property int alarmSoundInterval: Math.max(1, GlobalConfig.bar.clock.alarm.soundInterval)
    readonly property int alarmSoundDuration: Math.max(0, GlobalConfig.bar.clock.alarm.soundDuration)
    // A duration of 0 means a single chime.
    readonly property int alarmMaxPlays: alarmSoundDuration <= 0 ? 1 : Math.floor(alarmSoundDuration / alarmSoundInterval) + 1
    // Late by no more than this is treated as on time rather than missed. Covers
    // the one second check interval and short resumes from suspend.
    readonly property int alarmGraceMs: 60000

    property var _alarmNotification: null

    readonly property string stopwatchText: formatStopwatch(stopwatchElapsed)
    readonly property string countdownText: formatCountdown(countdownRemaining)
    readonly property bool countdownFinished: !countdownRunning && countdownRemaining <= 0

    function pad(value: int): string {
        return value < 10 ? "0" + value : value.toString();
    }

    function formatStopwatch(ms: real): string {
        const total = Math.max(0, Math.floor(ms));
        const hours = Math.floor(total / 3600000);
        const minutes = Math.floor(total / 60000) % 60;
        const seconds = Math.floor(total / 1000) % 60;
        const centis = Math.floor(total / 10) % 100;

        if (hours > 0)
            return hours + ":" + pad(minutes) + ":" + pad(seconds);
        return pad(minutes) + ":" + pad(seconds) + "." + pad(centis);
    }

    function formatCountdown(ms: real): string {
        const total = Math.max(0, Math.ceil(ms / 1000));
        const hours = Math.floor(total / 3600);
        const minutes = Math.floor(total / 60) % 60;
        const seconds = total % 60;

        if (hours > 0)
            return hours + ":" + pad(minutes) + ":" + pad(seconds);
        return pad(minutes) + ":" + pad(seconds);
    }

    function startStopwatch(): void {
        if (stopwatchRunning)
            return;
        _stopwatchBase = stopwatchElapsed;
        _stopwatchStartedAt = Date.now();
        stopwatchRunning = true;
    }

    function pauseStopwatch(): void {
        if (!stopwatchRunning)
            return;
        stopwatchElapsed = _stopwatchBase + (Date.now() - _stopwatchStartedAt);
        stopwatchRunning = false;
    }

    function toggleStopwatch(): void {
        if (stopwatchRunning)
            pauseStopwatch();
        else
            startStopwatch();
    }

    function resetStopwatch(): void {
        stopwatchRunning = false;
        stopwatchElapsed = 0;
        _stopwatchBase = 0;
    }

    function setCountdown(ms: int): void {
        countdownRunning = false;
        countdownDuration = Math.max(60000, ms);
        countdownRemaining = countdownDuration;
    }

    function startCountdown(): void {
        if (countdownRunning)
            return;
        if (countdownRemaining <= 0)
            countdownRemaining = countdownDuration;
        _countdownEndsAt = Date.now() + countdownRemaining;
        countdownRunning = true;
    }

    function pauseCountdown(): void {
        if (!countdownRunning)
            return;
        countdownRemaining = Math.max(0, _countdownEndsAt - Date.now());
        countdownRunning = false;
    }

    function toggleCountdown(): void {
        if (countdownRunning)
            pauseCountdown();
        else
            startCountdown();
    }

    function resetCountdown(): void {
        countdownRunning = false;
        countdownRemaining = countdownDuration;
    }

    function shiftCountdown(delta: int): void {
        const nextDuration = Math.max(60000, countdownDuration + delta);
        const applied = nextDuration - countdownDuration;
        countdownDuration = nextDuration;

        if (countdownRunning)
            _countdownEndsAt += applied;
        else
            countdownRemaining = Math.max(0, countdownRemaining + applied);
    }

    function nextAlarmOccurrence(hour: int, minute: int, fromMs: real): real {
        const next = new Date(fromMs);
        next.setHours(hour, minute, 0, 0);
        // A time that already passed today belongs to tomorrow.
        if (next.getTime() <= fromMs)
            next.setDate(next.getDate() + 1);
        return next.getTime();
    }

    function setAlarm(hour: int, minute: int): void {
        alarmProps.hour = Math.max(0, Math.min(23, Math.floor(hour)));
        alarmProps.minute = Math.max(0, Math.min(59, Math.floor(minute)));
        if (alarmProps.enabled)
            alarmProps.nextMs = nextAlarmOccurrence(alarmProps.hour, alarmProps.minute, Date.now());
    }

    // Wraps around midnight so the buttons never need a disabled state.
    function shiftAlarm(deltaMinutes: int): void {
        const total = (alarmProps.hour * 60 + alarmProps.minute + deltaMinutes + 1440) % 1440;
        setAlarm(Math.floor(total / 60), total % 60);
    }

    function enableAlarm(): void {
        stopAlarm();
        alarmProps.nextMs = nextAlarmOccurrence(alarmProps.hour, alarmProps.minute, Date.now());
        alarmProps.enabled = true;
    }

    function disableAlarm(): void {
        alarmProps.enabled = false;
        stopAlarm();
    }

    function snoozeAlarm(minutes: int): void {
        stopAlarm();
        alarmProps.nextMs = Date.now() + Math.max(1, minutes) * 60000;
        alarmProps.enabled = true;
    }

    function dismissAlarm(): void {
        alarmProps.enabled = false;
        stopAlarm();
    }

    function stopAlarm(): void {
        alarmRinging = false;
        _alarmPlays = 0;
        if (_alarmNotification) {
            _alarmNotification.close();
            _alarmNotification = null;
        }
    }

    function fireAlarm(): void {
        alarmProps.enabled = false;
        alarmRinging = true;
        _alarmPlays = 0;

        if (_alarmNotification)
            _alarmNotification.close();

        _alarmNotification = Notifs.addCustomNotification(Tr.tr("Alarm"), alarmText, "alarm", [
            { text: Tr.tr("Snooze 5 minutes"), invoke: () => root.snoozeAlarm(5) },
            { text: Tr.tr("Dismiss"), invoke: () => root.dismissAlarm() }
        ], true);
    }

    function checkAlarm(): void {
        if (!alarmProps.enabled || alarmRinging)
            return;

        const now = Date.now();
        if (now < alarmProps.nextMs)
            return;

        const lateBy = now - alarmProps.nextMs;
        if (lateBy <= alarmGraceMs) {
            fireAlarm();
            return;
        }

        // Missed by more than the grace window: the shell was off or the machine
        // was suspended through it. Let the user decide what that should mean.
        switch (GlobalConfig.bar.clock.alarm.missedAction) {
        case AlarmMissed.Ring:
            fireAlarm();
            break;
        case AlarmMissed.Skip:
            alarmProps.enabled = false;
            break;
        default:
            alarmProps.nextMs = nextAlarmOccurrence(alarmProps.hour, alarmProps.minute, now);
            break;
        }
    }

    function tick(): void {
        if (stopwatchRunning)
            stopwatchElapsed = _stopwatchBase + (Date.now() - _stopwatchStartedAt);

        if (countdownRunning) {
            countdownRemaining = Math.max(0, _countdownEndsAt - Date.now());
            if (countdownRemaining <= 0) {
                countdownRunning = false;
                Toaster.toast(Tr.tr("Timer"), Tr.tr("Time is up"), "timer");
            }
        }
    }

    Timer {
        interval: 50
        repeat: true
        running: root.stopwatchRunning || root.countdownRunning
        onTriggered: root.tick()
    }

    Timer {
        interval: 1000
        repeat: true
        running: alarmProps.enabled && !root.alarmRinging
        onTriggered: root.checkAlarm()
    }

    Timer {
        id: ringTimer

        interval: root.alarmSoundInterval * 1000
        repeat: true
        triggeredOnStart: true
        running: root.alarmRinging && root._alarmPlays < root.alarmMaxPlays
        onTriggered: {
            Audio.playAlarm();
            root._alarmPlays++;
        }
    }

    PersistentProperties {
        id: alarmProps

        property bool enabled: false
        property int hour: 7
        property int minute: 0
        property real nextMs: 0

        reloadableId: "clockAlarm"
    }
}
