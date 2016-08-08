## Unix Time 

Simple and portable D wrapper for POSIX Time (aka Unix Time)


### Rationale

While D has good datetime support from std.datetime, the internal representation is always
kept in stdtime (hecto-nanoseconds since Jan 1, 0 AD).  This necessitate constant conversion
to/from stdtime when all you want to deal with good ol' fashioned Unix Time.

UnixTime also allows you to more easily get at the raw clock values on your system and allows full
nanosecond resolution (assuming your arch supports it).

It is also very simple (no TZ  or date formatting/parsing) and basically tries to do the least
amount of work while still doing the "right thing" when all you want to get at is some clock values.

Converting to/from UnixTime/SysTime is easy via the provided methods so when you need it you have all
the power of std.datetime at your disposal.


### Basic Usage

```d
import unixtime : UnixTime, UnixTimeHiRes;

auto hiResNow = UnixTimeHiRes.now();

writeln(hiResNow.seconds); // 1470292916
writeln(hiResNow.nsecs); // 473318461


auto lowResNow = UnixTime.now();

writeln(lowResNow.seconds); // 1470292916
writeln(lowResNow.nsecs); // 473318461
```


### Addition and Subtraction

```d
// Basic addition of timestamps
UnixTime(500) + UnixTime(250) // UnixTime(750)
UnixTime(500) + UnixTime(-750) // UnixTime(-250)
UnixTime(time_t.max) + UnixTime(1) // overflow, throws exception

// And subtraction
UnixTime(500) - UnixTime(250) // UnixTime(250)
UnixTime(500) - UnixTime(-750) // UnixTime(1250)
UnixTime(time_t.min) - UnixTime(1) // underflow, throws exception

// Same thing with hi res, nanos will cause seconds to roll over
UnixTimeHiRes(500, 100) + UnixTimeHiRes(250, 250) // UnixTimeHiRese(750, 350)
UnixTimeHiRes(500) + UnixTimeHiRes(0, -500) // UnixTime(499, 999_999_500)
UnixTimeHiRes(time_t, 999_999_999) + UnixTime(0, 1) // overflow, throws exception

// Can mix and match hi res and normal, will return hi res
UnixTime(500) - UnixTimeRes(250) // UnixTimeHiRes(250, 0)
UnixTimeHiRes(500, 250) - UnixTime(-750) // UnixTimeHiRes(1250, 250)
UnixTime(time_t.min) - UnixTime(1) // underflow, throws exception
```


### Parsing / Display

```d
UnixTime.parse("123") // UnixTime(123)
UnixTimeHiRes.parse("123.123") // UnixTimeHiRes(123, 123000000)

to!string(UnixTime(123)) // "123"
to!string(UnixTimeHiRes(123, 123000000)) // "123.123000000"
```


### Conversion to/from SysTime

```d
cast(SysTime) UnixTime(0) // SysTime(1970-Jan-1 00:00:00 UTC)
cast(SysTime) UnixTimeHiRes(123, 123000000) // SysTime(1970-Jan-1 00:02:03.123 UTC)
cast(SysTime) UnixTime(time_t.max) // throws exception, SysTime can't represent this timestamp

UnixTime(SysTime.min) // UnixTime(-984472800485)
UnixTimeHiRes(SysTime.max) // UnixTimeHiRes(860201606885, 477580700)
```


### Multiple clock support

```d
// Pass the clock you want as template parameter
auto realtime = UnixTime!(ClockType.REALTIME).now();
auto monotonic = UnixTime!(ClockType.MONOTONIC).now();
auto boot = UnixTime!(ClockType.BOOTTIME).now();

// Also can just pass it in as a runtime parameter
auto realtime = UnixTime.now(ClockType.REALTIME);
auto monotonic = UnixTime.now(ClockType.MONOTONIC);
auto boot = UnixTime.now(ClockType.BOOTTIME);
```

NOTE: Clock support is of course architecture and kernel dependent.
Not all clocks are available so in many cases you may get the same clock
regardless of your ClockType.

As of right now just Linux and FreeBSD are supported.

#### Linux

|ClockType          |clockid_t                  |
|-------------------|---------------------------|
REALTIME            |CLOCK_REALTIME             |
MONOTONIC           |CLOCK_MONOTONIC            |
SECOND              |(uses core.stdc.time)      |
REALTIME_PRECISE    |CLOCK_REALTIME             |
REALTIME_FAST       |CLOCK_REALTIME_COARSET     |
MONOTONIC_FAST      |CLOCK_MONOTONIC_COARSE     |
MONOTONIC_PRECISE   |CLOCK_MONOTONIC_RAW        |
UPTIME              |CLOCK_BOOTTIME             |
UPTIME_FAST         |CLOCK_BOOTTIME             |
UPTIME_PRECISE      |CLOCK_BOOTTIME             |


#### FreeBSD

|ClockType          |clockid_t                  |
|-------------------|---------------------------|
REALTIME            |CLOCK_REALTIME             |
MONOTONIC           |CLOCK_MONOTONIC            |
SECOND              |CLOCK_SECOND               |
REALTIME_PRECISE    |CLOCK_REALTIME_PRECISE     |
REALTIME_FAST       |CLOCK_REALTIME_FAST        |
MONOTONIC_FAST      |CLOCK_MONOTONIC_FAST       |
MONOTONIC_PRECISE   |CLOCK_MONOTONIC_PRECISE    |
UPTIME              |CLOCK_UPTIME               |
UPTIME_FAST         |CLOCK_UPTIME_FAST          |
UPTIME_PRECISE      |CLOCK_UPTIME_PRECISE       |


### Author

Richard Farr, `<richard@nxbit.io>`

### Copyright & License

Copyright (c) 2016, Richard Farr
Permission to use, copy, modify, and/or distribute this software for any purpose with or without fee is hereby granted, provided that the above copyright notice and this permission notice appear in all copies.
THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

