module unixtime;

import core.checkedint : adds, subs, muls;
import core.sys.posix.sys.time : time_t;
import core.time : dur, convert;

import std.conv : to;
import std.exception : enforce;
import std.datetime : SysTime, TimeException, unixTimeToStdTime;
import std.format : format;
import std.math : abs;
import std.string : split, StringException;
import std.traits : Unqual;


// TODO windows, OSX, other BSDes, Solaris
version (linux) import core.sys.linux.time;
else version (FreeBSD) import core.sys.freebsd.time;
else static assert(false, "Unsupported OS");

@safe
struct UnixTime
{
    public:

        enum ClockType
        {
            REALTIME,
            REALTIME_FAST,
            REALTIME_PRECISE,
            MONOTONIC,
            MONOTONIC_FAST,
            MONOTONIC_PRECISE,
            UPTIME,
            UPTIME_FAST,
            UPTIME_PRECISE,
            SECOND
        }

        time_t seconds = void;
        long nanos = void;

        pure this(time_t seconds)
        {
            this.seconds = seconds;
            this.nanos = 0;
        }

        pure this(time_t seconds, long nanos)
        in
        {
            assert(nanos.abs < NANOS_IN_SECOND);
        }
        body
        {
            this.seconds = seconds;
            this.nanos = nanos;

            adjust(this.seconds, this.nanos);
        }

        pure this(const ref SysTime sysTime)
        {
            // Need to do some massaging to prevent underflow in this case
            if (sysTime.stdTime < long.min + UNIX_EPOCH_IN_STDTIME)
            {
                this.seconds = sysTime.stdTime / 10_000_000 - UNIX_EPOCH_IN_STDTIME / 10_000_000;
                this.nanos = sysTime.stdTime % 10_000_000 * 100;
            }
            else
            {
                immutable auto offset = sysTime.stdTime - UNIX_EPOCH_IN_STDTIME;
                this.seconds = offset / 10_000_000;
                this.nanos = offset % 10_000_000 * 100;
            }
        }

        pure SysTime opCast(T)() if (is(T == SysTime))
        in
        {
            assert(this.nanos.abs < NANOS_IN_SECOND);
        }
        body
        {
            enforce(this.seconds <= SysTime.max().toUnixTime() && this.seconds >= SysTime.min().toUnixTime());

            return SysTime(unixTimeToStdTime(this.seconds) + convert!("nsecs", "hnsecs")(nanos));
        }

        @nogc
        pure nothrow time_t opCast(T)() if (is(T == time_t))
        {
            return seconds;
        }

        pure UnixTime opAdd(const UnixTime other) const
        {
            return opAdd(other);
        }

        pure UnixTime opAdd(const ref UnixTime other) const
        in
        {
            assert(this.nanos.abs < NANOS_IN_SECOND);
            assert(other.nanos.abs < NANOS_IN_SECOND);
        }
        body
        {
            auto seconds = safelyAddSigned(this.seconds, other.seconds);
            long nanos = this.nanos + other.nanos;

            adjust(seconds, nanos);

            return UnixTime(seconds, nanos);

        }

        pure UnixTime opSub(const UnixTime other) const
        {
            return opSub(other);
        }

        pure UnixTime opSub(const ref UnixTime other) const
        in
        {
            assert(this.nanos.abs < NANOS_IN_SECOND);
            assert(other.nanos.abs < NANOS_IN_SECOND);
        }
        body
        {
            auto seconds = safelySubSigned(this.seconds, other.seconds);
            long nanos = this.nanos - other.nanos;

            adjust(seconds, nanos);

            return UnixTime(seconds, nanos);
        }

        string toString() const
        {
            return "%d.%09d".format(this.seconds, this.nanos.abs);
        }

        pure static UnixTime parse(string timestamp)
        {
            try
            {
                auto parts = timestamp.split(".");
                if (parts.length == 1)
                {
                    return UnixTime(to!time_t(parts[0]));
                }
                else if (parts.length == 2)
                {
                    if (parts[0].length == 0)
                    {
                        parts[0] = "0";
                    }

                    if (parts[1].length > 9)
                    {
                        parts[1] = parts[1][0..10];
                    }

                    return UnixTime(to!time_t(parts[0]), to!long(parts[1]) * 10 ^^ (9 - parts[1].length));
                }
            }
            catch (Exception e)
            {
            }
            throw new StringException("Invalid timestamp: " ~ timestamp);
        }

        @trusted
        static UnixTime now(ClockType clockType = ClockType.REALTIME)
        {
            version(linux)
            {
                if(clockType == ClockType.SECOND)
                {
                    return UnixTime(core.stdc.time.time(null));
                }
                else
                {
                    timespec ts;
                    if(clock_gettime(getArchClock(clockType), &ts) != 0)
                    {
                        // TODO perror
                        throw new TimeException("Call to clock_gettime() failed");
                    }

                    return UnixTime(ts.tv_sec, ts.tv_nsec);
                }
            }
            else version(FreeBSD)
            {
                timespec ts;
                if(clock_gettime(getArchClock(clockType), &ts) != 0)
                {
                    throw new TimeException("Call to clock_gettime() failed");
                }

                return UnixTime(ts.tv_sec, ts.tv_nsec);
            }
        }

        @trusted
        static UnixTime now(ClockType clockType = ClockType.REALTIME)()
        {
            return now(clockType);
        }

    private:

        enum NANOS_IN_SECOND = 1_000_000_000;
        enum UNIX_EPOCH_IN_STDTIME = 621_355_968_000_000_000L;

        pure static auto getArchClock(ClockType clockType)
        {
            version(linux)
            {
                switch(clockType)
                {
                    case (ClockType.REALTIME):
                    case (ClockType.MONOTONIC):             return CLOCK_MONOTONIC;
                    case (ClockType.REALTIME_PRECISE):      return CLOCK_REALTIME;
                    case (ClockType.REALTIME_FAST):         return CLOCK_REALTIME_COARSE;
                    case (ClockType.MONOTONIC_FAST):        return CLOCK_MONOTONIC_COARSE;
                    case (ClockType.MONOTONIC_PRECISE):     return CLOCK_MONOTONIC_RAW;
                    case (ClockType.UPTIME):
                    case (ClockType.UPTIME_FAST):
                    case (ClockType.UPTIME_PRECISE):        return CLOCK_BOOTTIME;

                    default:
                        assert(false, "ClockType=" ~ to!string(clockType) ~ " not supported on this platform");
                }
            }
            else version (FreeBSD)
            {
                switch(clockType)
                {
                    case (ClockType.REALTIME):              return CLOCK_REALTIME;
                    case (ClockType.MONOTONIC):             return CLOCK_MONOTONIC;
                    case (ClockType.SECOND):                return CLOCK_SECOND;
                    case (ClockType.REALTIME_PRECISE):      return CLOCK_REALTIME_PRECISE;
                    case (ClockType.REALTIME_FAST):         return CLOCK_REALTIME_FAST;
                    case (ClockType.MONOTONIC_FAST):        return CLOCK_MONOTONIC_FAST;
                    case (ClockType.MONOTONIC_PRECISE):     return CLOCK_MONOTONIC_PRECISE;
                    case (ClockType.UPTIME):                return CLOCK_UPTIME;
                    case (ClockType.UPTIME_FAST):           return CLOCK_UPTIME_FAST;
                    case (ClockType.UPTIME_PRECISE):        return CLOCK_UPTIME_PRECISE;

                    default:
                        assert(false, "ClockType=" ~ to!string(clockType) ~ " not supported on this platform");
                }
            }
        }

        pure static auto safelyAddSigned(First, Remaining...)(First first, Remaining operands)
        {
            bool overflow = false;
            Unqual!First accumulator = first;

            foreach(operand; operands)
            {
                accumulator = adds(accumulator, operand, overflow);
            }

            if (overflow)
            {
                throw new TimeException("Overflowed");
            }

            return accumulator;
        }

        pure static auto safelySubSigned(First, Remaining...)(First first, Remaining operands)
        {
            bool underflow = false;
            Unqual!First accumulator = first;

            foreach(operand; operands)
            {
                accumulator = subs(accumulator, operand, underflow);
            }

            if (underflow)
            {
                throw new TimeException("Underflowed");
            }

            return accumulator;
        }

        pure static void adjust(ref time_t seconds, ref long nanos)
        {
            if (seconds > 0)
            {
                if (nanos >= NANOS_IN_SECOND)
                {
                    seconds = safelyAddSigned(seconds, 1);
                    nanos -= NANOS_IN_SECOND;
                }
                else if (nanos < 0)
                {
                    seconds--;
                    nanos += NANOS_IN_SECOND;
                }
            }
            else if (seconds < 0)
            {
                if (nanos <= -NANOS_IN_SECOND)
                {
                    seconds = safelySubSigned(seconds, 1);
                    nanos += NANOS_IN_SECOND;
                }
                else if (nanos > 0)
                {
                    seconds++;
                    nanos -= NANOS_IN_SECOND;
                }
            }
        }
}

version(unittest)
{
    import core.exception : AssertError;
    import std.array : join;
    import std.stdio : write, writeln;
    import std.exception : assertThrown;
}

unittest
{
    writeln("[UnitTest UnixTime] - constructor");

    auto time = UnixTime(0);
    assert(time.seconds == 0);
    assert(time.nanos == 0);

    time = UnixTime(500, 1);
    assert(time.seconds == 500);
    assert(time.nanos == 1);

    time = UnixTime(500, -1);
    assert(time.seconds == 499);
    assert(time.nanos == 999_999_999);

    time = UnixTime(-500, -1);
    assert(time.seconds == -500);
    assert(time.nanos == -1);

    time = UnixTime(-500, 1);
    assert(time.seconds == -499);
    assert(time.nanos == -999_999_999);
}

unittest
{
    writeln("[UnitTest UnixTime] - SysTime constructor");

    auto sysTime = SysTime(UnixTime.UNIX_EPOCH_IN_STDTIME);
    auto time = UnixTime(sysTime);
    assert(time.seconds == 0);
    assert(time.nanos == 0);

    sysTime = SysTime(UnixTime.UNIX_EPOCH_IN_STDTIME + 1);
    time = UnixTime(sysTime);
    assert(time.seconds == 0);
    assert(time.nanos == 100);

    sysTime = SysTime(UnixTime.UNIX_EPOCH_IN_STDTIME - 1);
    time = UnixTime(sysTime);
    assert(time.seconds == 0);
    assert(time.nanos == -100);

    sysTime = SysTime(UnixTime.UNIX_EPOCH_IN_STDTIME + 10_000_000);
    time = UnixTime(sysTime);
    assert(time.seconds == 1);
    assert(time.nanos == 0);

    sysTime = SysTime(UnixTime.UNIX_EPOCH_IN_STDTIME - 10_000_000);
    time = UnixTime(sysTime);
    assert(time.seconds == -1);
    assert(time.nanos == 0);

    sysTime = SysTime.min;
    time = UnixTime(sysTime);
    assert(time.seconds == -984472800485);
    assert(time.nanos == -477580800);

    sysTime = SysTime.max;
    time = UnixTime(sysTime);
    assert(time.seconds == 860201606885);
    assert(time.nanos == 477580700);
}

unittest
{
    writeln("[UnitTest UnixTime] - parse");

    auto time = UnixTime.parse("0");
    assert(time.seconds == 0);
    assert(time.nanos == 0);

    time = UnixTime.parse("12345");
    assert(time.seconds == 12345);
    assert(time.nanos == 0);

    time = UnixTime.parse("12345.12345");
    assert(time.seconds == 12345);
    assert(time.nanos == 123450000);

    time = UnixTime.parse("0.999999999");
    assert(time.seconds == 0);
    assert(time.nanos == 999_999_999);

    time = UnixTime.parse("0.000000001");
    assert(time.seconds == 0);
    assert(time.nanos == 1);

    time = UnixTime.parse("0.000000000");
    assert(time.seconds == 0);
    assert(time.nanos == 0);

    time = UnixTime.parse("0.0000000009");
    assert(time.seconds == 0);
    assert(time.nanos == 0);

    time = UnixTime.parse(".9");
    assert(time.seconds == 0);
    assert(time.nanos == 900_000_000);

    assertThrown!StringException(UnixTime.parse(""));
    assertThrown!StringException(UnixTime.parse("a"));
    assertThrown!StringException(UnixTime.parse("0.1.2"));
    assertThrown!StringException(UnixTime.parse("123..7"));

    static if (is(time_t == int))
    {
        assertThrown!StringException(UnixTime.parse("2147483648"));
    }
    else if (is(time_t == long))
    {
        assertThrown!StringException(UnixTime.parse("9223372036854775808"));
    }
    else
    {
        assert(false, "Unknown type for time_t.  Must be int or long");
    }
}

unittest
{
    writeln("[UnitTest UnixTime] - opAdd");

    // Normal case, no overflow of either seconds or nanos
    auto sum = UnixTime(1000, 1000) + UnixTime(1000, 1000);
    assert(sum.seconds == 2000);
    assert(sum.nanos == 2000);

    // Overflow of nanos
    sum = UnixTime(1000, 1000) + UnixTime(1000, 999_999_999);
    assert(sum.seconds == 2001);
    assert(sum.nanos == 999);

    // Assertion failure when lhs nanos is >= NANOS_IN_SECOND
    auto time = UnixTime(0, 0);
    time.nanos = UnixTime.NANOS_IN_SECOND;
    assertThrown!AssertError(time + UnixTime(0, 0));
    assertThrown!AssertError(UnixTime(0, 0) + time);

    // Boundary, just on overflow, no nanos overflow
    sum = UnixTime(time_t.max - 1000) + UnixTime(1000);
    assert(sum.seconds == time_t.max);
    assert(sum.nanos == 0);

    // Overflow of seconds
    assertThrown!TimeException(UnixTime(time_t.max - 999) + UnixTime(1000));

    // Overflow of nanos causing overflow of seconds
    assertThrown!TimeException(UnixTime(time_t.max - 1000, 500) + UnixTime(1000, 999_999_500));

    // Underflow of seconds
    assertThrown!TimeException(UnixTime(time_t.min) + UnixTime(-1));

    // Sum min and max times
    sum = UnixTime(time_t.min, -999_999_999) + UnixTime(time_t.max, 999_999_999);

    assert(sum.seconds == -1);
    assert(sum.nanos == 0);

    // Sum min times
    assertThrown!TimeException(UnixTime(time_t.min, -999_999_999) + UnixTime(time_t.min, -999_999_999));


    // Positive to negative
    sum = UnixTime(0, 500) + UnixTime(0, -1000);

    assert(sum.seconds == 0);
    assert(sum.nanos == -500);


    // Negative to positive
    sum = UnixTime(0, -500) + UnixTime(0, 1000);

    assert(sum.seconds == 0);
    assert(sum.nanos == 500);


    // Positive to zero
    sum = UnixTime(1, -999_999_999) + UnixTime(0, -1);

    assert(sum.seconds == 0);
    assert(sum.nanos == 0);
}

unittest
{
    writeln("[UnitTest UnixTime] - opSub");

    // Normal case, no underflow of either seconds or nanos
    auto diff = UnixTime(2000, 2000) - UnixTime(1000, 1000);
    assert(diff.seconds == 1000);
    assert(diff.nanos == 1000);

    // Underflow of nanos
    diff = UnixTime(2000, 2000) - UnixTime(1000, 999_999_999);
    assert(diff.seconds == 999);
    assert(diff.nanos == 2001);

    // Assertion failure when lhs nanos is >= NANOS_IN_SECOND
    auto time = UnixTime(0, 0);
    time.nanos = UnixTime.NANOS_IN_SECOND;
    assertThrown!AssertError(time - UnixTime(0, 0));
    assertThrown!AssertError(UnixTime(0, 0) - time);

    // Boundary, just on underflow, no nanos underflow
    diff = UnixTime(time_t.min + 1000) - UnixTime(1000);
    assert(diff.seconds == time_t.min);
    assert(diff.nanos == 0);

    // Underflow of seconds
    assertThrown!TimeException(UnixTime(time_t.min + 999) - UnixTime(1000));

    // Underflow of nanos causing underflow of seconds
    assertThrown!TimeException(UnixTime(time_t.min + 1000, -500) - UnixTime(1000, 999_999_500));

    // Diff max and max times
    diff = UnixTime(time_t.max, 999_999_999) - UnixTime(time_t.max, 999_999_999);

    assert(diff.seconds == 0);
    assert(diff.nanos == 0);

    // Positive to negative
    diff = UnixTime(0, 500) - UnixTime(0, 1000);

    assert(diff.seconds == 0);
    assert(diff.nanos == -500);


    // Negative to positive
    diff = UnixTime(0, -500) - UnixTime(0, -1000);

    assert(diff.seconds == 0);
    assert(diff.nanos == 500);


    // Negative to zero
    diff = UnixTime(-1, 999_999_999) - UnixTime(0, -1);

    assert(diff.seconds == 0);
    assert(diff.nanos == 0);
}

unittest
{
    writeln("[UnitTest UnixTime] - opCast Systime");

    enum hnsecsToUnixEpoch = unixTimeToStdTime(0);

    auto time = UnixTime(0, 0);
    SysTime systime = cast(SysTime)time;
    assert(systime.toUnixTime() == 0);
    assert(systime.stdTime == hnsecsToUnixEpoch);

    time = UnixTime(0, 999_999_999);
    systime = cast(SysTime)time;
    assert(systime.toUnixTime() == time.seconds);
    assert(systime.stdTime == hnsecsToUnixEpoch + convert!("nsecs", "hnsecs")(time.nanos));

    time = UnixTime(5_000, 0);
    systime = cast(SysTime)time;
    assert(systime.toUnixTime() == time.seconds);
    assert(systime.stdTime == hnsecsToUnixEpoch + convert!("seconds", "hnsecs")(time.seconds));

    time = UnixTime(1_470_014_173, 172_399);
    systime = cast(SysTime)time;
    assert(systime.toUnixTime() == time.seconds);
    assert(systime.stdTime == hnsecsToUnixEpoch + convert!("seconds", "hnsecs")(time.seconds) + convert!("nsecs", "hnsecs")(time.nanos));

    time = UnixTime(SysTime.max().toUnixTime(), 0);
    systime = cast(SysTime)time;
    assert(systime.toUnixTime() == time.seconds);
    assert(systime.stdTime == hnsecsToUnixEpoch + convert!("seconds", "hnsecs")(time.seconds));

    time = UnixTime(SysTime.max().toUnixTime(), SysTime.max().fracSecs.split!("seconds", "nsecs")().nsecs);
    systime = cast(SysTime)time;
    assert(systime.toUnixTime() == time.seconds);
    assert(systime.stdTime == hnsecsToUnixEpoch + convert!("seconds", "hnsecs")(time.seconds) + convert!("nsecs", "hnsecs")(time.nanos));

    time = UnixTime(SysTime.min().toUnixTime(), 0);
    systime = cast(SysTime)time;
    assert(systime.toUnixTime() == time.seconds);
    //TODO fix when phobos bug fixed
    //assert(systime.stdTime == hnsecsToUnixEpoch - convert!("seconds", "hnsecs")(time.seconds));

    //time = UnixTime(SysTime.min().toUnixTime(), SysTime.min().fracSecs.split!("seconds", "nsecs")().nanos);
    //systime = cast(SysTime)time;
    //assert(systime.toUnixTime() == time.seconds);
    //assert(systime.stdTime == hnsecsToUnixEpoch - convert!("seconds", "hnsecs")(time.seconds) - convert!("nsecs", "hnsecs")(time.nanos));
}

unittest
{
    writeln("[UnitTest UnixTime] - opCast time_t");

    auto time = UnixTime(0, 0);
    assert(cast(time_t)time == 0);

    time = UnixTime(time_t.max, 999_999_999);
    assert(cast(time_t)time == time_t.max);

    time = UnixTime(time_t.min, -999_999_999);
    assert(cast(time_t)time == time_t.min);
}

unittest
{
    writeln("[UnitTest UnixTime] - CTFE now");

    UnixTime.now!(UnixTime.ClockType.SECOND)();
    UnixTime.now!(UnixTime.ClockType.REALTIME)();
    UnixTime.now!(UnixTime.ClockType.REALTIME_FAST)();
    UnixTime.now!(UnixTime.ClockType.REALTIME_PRECISE)();
    UnixTime.now!(UnixTime.ClockType.MONOTONIC)();
    UnixTime.now!(UnixTime.ClockType.MONOTONIC_FAST)();
    UnixTime.now!(UnixTime.ClockType.MONOTONIC_PRECISE)();
    UnixTime.now!(UnixTime.ClockType.UPTIME)();
    UnixTime.now!(UnixTime.ClockType.UPTIME_FAST)();
    UnixTime.now!(UnixTime.ClockType.UPTIME_PRECISE)();
}

unittest
{
    writeln("[UnitTest UnixTime] - now");

    UnixTime.now(UnixTime.ClockType.SECOND);
    UnixTime.now(UnixTime.ClockType.REALTIME);
    UnixTime.now(UnixTime.ClockType.REALTIME_FAST);
    UnixTime.now(UnixTime.ClockType.REALTIME_PRECISE);
    UnixTime.now(UnixTime.ClockType.MONOTONIC);
    UnixTime.now(UnixTime.ClockType.MONOTONIC_FAST);
    UnixTime.now(UnixTime.ClockType.MONOTONIC_PRECISE);
    UnixTime.now(UnixTime.ClockType.UPTIME);
    UnixTime.now(UnixTime.ClockType.UPTIME_FAST);
    UnixTime.now(UnixTime.ClockType.UPTIME_PRECISE);
}

unittest
{
    writeln("[UnitTest UnixTime] - toString");

    assert(UnixTime(0).toString() == "0.000000000");

    assert(UnixTime(-100).toString() == "-100.000000000");
    assert(UnixTime(-100, 1).toString() == "-99.999999999");
    assert(UnixTime(-100, -1).toString() == "-100.000000001");
    assert(UnixTime(-100, 999999999).toString() == "-99.000000001");
    assert(UnixTime(-100, -999999999).toString() == "-100.999999999");

    assert(UnixTime(100).toString() == "100.000000000");
    assert(UnixTime(100, 1).toString() == "100.000000001");
    assert(UnixTime(100, -1).toString() == "99.999999999");
    assert(UnixTime(100, 999999999).toString() == "100.999999999");
    assert(UnixTime(100, -999999999).toString() == "99.000000001");
}
