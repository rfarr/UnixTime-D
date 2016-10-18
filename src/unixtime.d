module unixtime;

import core.checkedint : adds, subs, muls;
import core.sys.posix.sys.time : time_t;
import core.time : dur, convert;

import std.conv : to;
import std.exception : enforce, ErrnoException;
import std.datetime : SysTime;
import std.format : format;
import std.math : abs;
import std.string : split, StringException;
import std.traits : Unqual;


// TODO windows, OSX, other BSDes, Solaris
version (linux) import core.sys.linux.time;
else version (FreeBSD) import core.sys.freebsd.time;
else static assert(false, "Unsupported OS");

alias UnixTimeHiRes = SystemClock!true;
alias UnixTime = SystemClock!false;

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

@safe
struct SystemClock(bool HiRes)
{
    public:

        enum Epoch = SystemClock!HiRes(0);

        time_t seconds;
        static if (HiRes)
        {
            long nanos;
        }

        @nogc
        pure nothrow this(time_t seconds)
        {
            this.seconds = seconds;
        }

        static if (HiRes)
        {
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
        }

        pure nothrow this(const SysTime sysTime)
        {
            this(sysTime);
        }

        pure nothrow this(const ref SysTime sysTime)
        {
            this.seconds = stdTimeToUnixTime(sysTime.stdTime);
            static if (HiRes)
            {
                // Need to massage a bit to prevent underflow
                if (sysTime.stdTime < long.min + UNIX_EPOCH_IN_STDTIME)
                {
                    this.nanos = (sysTime.stdTime % 10_000_000 - UNIX_EPOCH_IN_STDTIME % 10_000_000) * 100;
                }
                else
                {
                    this.nanos = (sysTime.stdTime - UNIX_EPOCH_IN_STDTIME) % 10_000_000 * 100;
                }
            }
        }

        pure SysTime opCast(T)() const if (is(T == SysTime))
        in
        {
            static if (HiRes)
            {
                assert(this.nanos.abs < NANOS_IN_SECOND);
            }
        }
        body
        {
            enforce(this.seconds <= MAX_STDTIME_IN_UNIXTIME && this.seconds >= MIN_STDTIME_IN_UNIXTIME);

            static if (HiRes)
            {
                return SysTime(unixTimeToStdTime(this.seconds) + this.nanos / 100);
            }
            else
            {
                return SysTime(unixTimeToStdTime(this.seconds));
            }
        }

        @nogc
        pure nothrow time_t opCast(T)() const if (is(T == time_t))
        {
            return seconds;
        }

        static if (HiRes)
        {
            @nogc
            pure nothrow UnixTime opCast(T)() const if (is(T == UnixTime))
            {
                return UnixTime(this.seconds);
            }

            pure UnixTimeHiRes opAdd(const UnixTime other) const
            {
                return this + cast(UnixTimeHiRes) other.seconds;
            }

            pure UnixTimeHiRes opAdd(const UnixTimeHiRes other) const
            {
                return opAdd(other);
            }

            pure UnixTimeHiRes opAdd(const ref UnixTimeHiRes other) const
            in
            {
                static if (HiRes)
                {
                    assert(this.nanos.abs < NANOS_IN_SECOND);
                    assert(other.nanos.abs < NANOS_IN_SECOND);
                }
            }
            body
            {
                auto seconds = safelyAddSigned(this.seconds, other.seconds);

                static if (HiRes)
                {
                    long nanos = this.nanos + other.nanos;
                    adjust(seconds, nanos);
                    return UnixTimeHiRes(seconds, nanos);
                }
                else
                {
                    return UnixTimeHiRes(seconds);
                }
            }

            pure UnixTimeHiRes opSub(const UnixTime other) const
            {
                return this - cast(UnixTimeHiRes) other;
            }

            pure UnixTimeHiRes opSub(const UnixTimeHiRes other) const
            {
                return opSub(other);
            }

            pure UnixTimeHiRes opSub(const ref UnixTimeHiRes other) const
            in
            {
                static if (HiRes)
                {
                    assert(this.nanos.abs < NANOS_IN_SECOND);
                    assert(other.nanos.abs < NANOS_IN_SECOND);
                }
            }
            body
            {
                auto seconds = safelySubSigned(this.seconds, other.seconds);

                static if (HiRes)
                {
                    long nanos = this.nanos - other.nanos;
                    adjust(seconds, nanos);
                    return UnixTimeHiRes(seconds, nanos);
                }
                else
                {
                    return UnixTimeHiRes(seconds);
                }
            }
        }
        else
        {
            @nogc
            pure nothrow UnixTimeHiRes opCast(T)() const if (is(T == UnixTimeHiRes))
            {
                return UnixTimeHiRes(this.seconds);
            }

            pure UnixTime opAdd(const UnixTime other) const
            {
                return UnixTime(safelyAddSigned(this.seconds, other.seconds));
            }

            pure UnixTimeHiRes opAdd(const UnixTimeHiRes other) const
            {
                return opAdd(other);
            }

            pure UnixTimeHiRes opAdd(const ref UnixTimeHiRes other) const
            {
                return cast(UnixTimeHiRes) this + other;
            }

            pure UnixTime opSub(const UnixTime other) const
            {
                return UnixTime(safelySubSigned(this.seconds, other.seconds));
            }

            pure UnixTimeHiRes opSub(const UnixTimeHiRes other) const
            {
                return opSub(other);
            }

            pure UnixTimeHiRes opSub(const ref UnixTimeHiRes other) const
            {
                return cast(UnixTimeHiRes) this - other;
            }
        }

        pure nothrow string toString()() const if (!HiRes)
        {
            return to!string(this.seconds);
        }

        pure string toString()() const if (HiRes)
        {
            return "%d.%09d".format(this.seconds, this.nanos.abs);
        }

        pure static UnixTime parse()(string timestamp) if (!HiRes)
        {
            try
            {
                return UnixTime(to!time_t(timestamp));
            }
            catch (Exception e)
            {
            }

            throw new StringException("Invalid timestamp: " ~ timestamp);
        }

        pure static UnixTimeHiRes parse()(string timestamp) if (HiRes)
        {
            try
            {
                auto parts = timestamp.split(".");

                if (parts.length == 1)
                {
                    return UnixTimeHiRes(to!time_t(parts[0]));
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

                    return UnixTimeHiRes(to!time_t(parts[0]), to!long(parts[1]) * 10 ^^ (9 - parts[1].length));
                }
            }
            catch (Exception e)
            {
            }

            throw new StringException("Invalid timestamp: " ~ timestamp);
        }

        static if (HiRes)
        {
            static UnixTimeHiRes now(ClockType clockType = ClockType.REALTIME)()
            {
                return now(clockType);
            }

            static UnixTimeHiRes now(ClockType clockType = ClockType.REALTIME)
            {
                UnixTimeHiRes timestamp;
                clockGettime(clockType, timestamp.seconds, timestamp.nanos);
                return timestamp;
            }
        }
        else
        {
            static UnixTime now(ClockType clockType = ClockType.REALTIME)()
            {
                return now(clockType);
            }

            static UnixTime now(ClockType clockType = ClockType.REALTIME)
            {
                UnixTime timestamp;
                long nanos;
                clockGettime(clockType, timestamp.seconds, nanos);
                return timestamp;
            }
        }

        @trusted
        static void clockGettime(ClockType clockType, out time_t seconds, out long nanos)
        {
            version(linux)
            {
                if(clockType == ClockType.SECOND)
                {
                    seconds = core.stdc.time.time(null);
                }
                else
                {
                    timespec ts;
                    if(clock_gettime(getArchClock(clockType), &ts) != 0)
                    {
                        throw new ErrnoException("Call to clock_gettime() failed");
                    }

                    seconds = ts.tv_sec;
                    nanos = ts.tv_nsec;
                }
            }
            else version(FreeBSD)
            {
                timespec ts;
                if(clock_gettime(getArchClock(clockType), &ts) != 0)
                {
                    throw new ErrnoException("Call to clock_gettime() failed");
                }

                seconds = ts.tv_sec;
                nanos = ts.tv_nsec;
            }
        }

    private:

        static immutable enum NANOS_IN_SECOND = 1_000_000_000;
        static immutable enum UNIX_EPOCH_IN_STDTIME = 621_355_968_000_000_000L;

        static immutable enum MIN_STDTIME_IN_UNIXTIME = stdTimeToUnixTime(SysTime.min.stdTime);
        static immutable enum MAX_STDTIME_IN_UNIXTIME = stdTimeToUnixTime(SysTime.max.stdTime);

        @nogc
        pure nothrow static time_t stdTimeToUnixTime(long stdTime)
        {
            // Need to do some massaging to prevent underflow in this case
            if (stdTime < long.min + UNIX_EPOCH_IN_STDTIME)
            {
                return stdTime / 10_000_000 - UNIX_EPOCH_IN_STDTIME / 10_000_000;
            }
            else
            {
                return (stdTime - UNIX_EPOCH_IN_STDTIME) / 10_000_000;
            }
        }

        @nogc
        pure nothrow static long unixTimeToStdTime(time_t unixTime)
        {
            return unixTime * 10_000_000 + UNIX_EPOCH_IN_STDTIME;
        }

        pure static auto getArchClock(ClockType clockType)
        {
            version(linux)
            {
                switch(clockType)
                {
                    case (ClockType.REALTIME):              return CLOCK_REALTIME;
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
                throw new Exception("Overflowed");
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
                throw new Exception("Underflowed");
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
    writeln("[UnitTest UnixTimeHiRes] - constructor");

    auto time = UnixTimeHiRes(0);
    assert(time.seconds == 0);
    assert(time.nanos == 0);

    time = UnixTimeHiRes(500, 1);
    assert(time.seconds == 500);
    assert(time.nanos == 1);

    time = UnixTimeHiRes(500, -1);
    assert(time.seconds == 499);
    assert(time.nanos == 999_999_999);

    time = UnixTimeHiRes(-500, -1);
    assert(time.seconds == -500);
    assert(time.nanos == -1);

    time = UnixTimeHiRes(-500, 1);
    assert(time.seconds == -499);
    assert(time.nanos == -999_999_999);
}

unittest
{
    writeln("[UnitTest UnixTimeHiRes] - SysTime constructor");

    auto sysTime = SysTime(UnixTimeHiRes.UNIX_EPOCH_IN_STDTIME);
    auto time = UnixTimeHiRes(sysTime);
    assert(time.seconds == 0);
    assert(time.nanos == 0);

    sysTime = SysTime(UnixTimeHiRes.UNIX_EPOCH_IN_STDTIME + 1);
    time = UnixTimeHiRes(sysTime);
    assert(time.seconds == 0);
    assert(time.nanos == 100);

    sysTime = SysTime(UnixTimeHiRes.UNIX_EPOCH_IN_STDTIME - 1);
    time = UnixTimeHiRes(sysTime);
    assert(time.seconds == 0);
    assert(time.nanos == -100);

    sysTime = SysTime(UnixTimeHiRes.UNIX_EPOCH_IN_STDTIME + 10_000_000);
    time = UnixTimeHiRes(sysTime);
    assert(time.seconds == 1);
    assert(time.nanos == 0);

    sysTime = SysTime(UnixTimeHiRes.UNIX_EPOCH_IN_STDTIME - 10_000_000);
    time = UnixTimeHiRes(sysTime);
    assert(time.seconds == -1);
    assert(time.nanos == 0);

    sysTime = SysTime.min;
    time = UnixTimeHiRes(sysTime);
    assert(time.seconds == -984472800485);
    assert(time.nanos == -477580800);

    sysTime = SysTime.max;
    time = UnixTimeHiRes(sysTime);
    assert(time.seconds == 860201606885);
    assert(time.nanos == 477580700);
}

unittest
{
    writeln("[UnitTest UnixTimeHiRes] - parse");

    auto time = UnixTimeHiRes.parse("0");
    assert(time.seconds == 0);
    assert(time.nanos == 0);

    time = UnixTimeHiRes.parse("12345");
    assert(time.seconds == 12345);
    assert(time.nanos == 0);

    time = UnixTimeHiRes.parse("12345.12345");
    assert(time.seconds == 12345);
    assert(time.nanos == 123450000);

    time = UnixTimeHiRes.parse("0.999999999");
    assert(time.seconds == 0);
    assert(time.nanos == 999_999_999);

    time = UnixTimeHiRes.parse("0.000000001");
    assert(time.seconds == 0);
    assert(time.nanos == 1);

    time = UnixTimeHiRes.parse("0.000000000");
    assert(time.seconds == 0);
    assert(time.nanos == 0);

    time = UnixTimeHiRes.parse("0.0000000009");
    assert(time.seconds == 0);
    assert(time.nanos == 0);

    time = UnixTimeHiRes.parse(".9");
    assert(time.seconds == 0);
    assert(time.nanos == 900_000_000);

    assertThrown!StringException(UnixTimeHiRes.parse(""));
    assertThrown!StringException(UnixTimeHiRes.parse("a"));
    assertThrown!StringException(UnixTimeHiRes.parse("0.1.2"));
    assertThrown!StringException(UnixTimeHiRes.parse("123..7"));

    static if (is(time_t == int))
    {
        assertThrown!StringException(UnixTimeHiRes.parse("2147483648"));
    }
    else if (is(time_t == long))
    {
        assertThrown!StringException(UnixTimeHiRes.parse("9223372036854775808"));
    }
    else
    {
        assert(false, "Unknown type for time_t.  Must be int or long");
    }
}

unittest
{
    writeln("[UnitTest UnixTimeHiRes] - opAdd");

    // Normal case, no overflow of either seconds or nanos
    auto sum = UnixTimeHiRes(1000, 1000) + UnixTimeHiRes(1000, 1000);
    assert(sum.seconds == 2000);
    assert(sum.nanos == 2000);

    // Overflow of nanos
    sum = UnixTimeHiRes(1000, 1000) + UnixTimeHiRes(1000, 999_999_999);
    assert(sum.seconds == 2001);
    assert(sum.nanos == 999);

    // Assertion failure when lhs nanos is >= NANOS_IN_SECOND
    auto time = UnixTimeHiRes(0, 0);
    time.nanos = UnixTimeHiRes.NANOS_IN_SECOND;
    assertThrown!AssertError(time + UnixTimeHiRes(0, 0));
    assertThrown!AssertError(UnixTimeHiRes(0, 0) + time);

    // Boundary, just on overflow, no nanos overflow
    sum = UnixTimeHiRes(time_t.max - 1000) + UnixTimeHiRes(1000);
    assert(sum.seconds == time_t.max);
    assert(sum.nanos == 0);

    // Overflow of seconds
    assertThrown!Exception(UnixTimeHiRes(time_t.max - 999) + UnixTimeHiRes(1000));

    // Overflow of nanos causing overflow of seconds
    assertThrown!Exception(UnixTimeHiRes(time_t.max - 1000, 500) + UnixTimeHiRes(1000, 999_999_500));

    // Underflow of seconds
    assertThrown!Exception(UnixTimeHiRes(time_t.min) + UnixTimeHiRes(-1));

    // Sum min and max times
    sum = UnixTimeHiRes(time_t.min, -999_999_999) + UnixTimeHiRes(time_t.max, 999_999_999);

    assert(sum.seconds == -1);
    assert(sum.nanos == 0);

    // Sum min times
    assertThrown!Exception(UnixTimeHiRes(time_t.min, -999_999_999) + UnixTimeHiRes(time_t.min, -999_999_999));


    // Positive to negative
    sum = UnixTimeHiRes(0, 500) + UnixTimeHiRes(0, -1000);

    assert(sum.seconds == 0);
    assert(sum.nanos == -500);


    // Negative to positive
    sum = UnixTimeHiRes(0, -500) + UnixTimeHiRes(0, 1000);

    assert(sum.seconds == 0);
    assert(sum.nanos == 500);


    // Positive to zero
    sum = UnixTimeHiRes(1, -999_999_999) + UnixTimeHiRes(0, -1);

    assert(sum.seconds == 0);
    assert(sum.nanos == 0);
}

unittest
{
    writeln("[UnitTest UnixTimeHiRes] - opSub");

    // Normal case, no underflow of either seconds or nanos
    auto diff = UnixTimeHiRes(2000, 2000) - UnixTimeHiRes(1000, 1000);
    assert(diff.seconds == 1000);
    assert(diff.nanos == 1000);

    // Underflow of nanos
    diff = UnixTimeHiRes(2000, 2000) - UnixTimeHiRes(1000, 999_999_999);
    assert(diff.seconds == 999);
    assert(diff.nanos == 2001);

    // Assertion failure when lhs nanos is >= NANOS_IN_SECOND
    auto time = UnixTimeHiRes(0, 0);
    time.nanos = UnixTimeHiRes.NANOS_IN_SECOND;
    assertThrown!AssertError(time - UnixTimeHiRes(0, 0));
    assertThrown!AssertError(UnixTimeHiRes(0, 0) - time);

    // Boundary, just on underflow, no nanos underflow
    diff = UnixTimeHiRes(time_t.min + 1000) - UnixTimeHiRes(1000);
    assert(diff.seconds == time_t.min);
    assert(diff.nanos == 0);

    // Underflow of seconds
    assertThrown!Exception(UnixTimeHiRes(time_t.min + 999) - UnixTimeHiRes(1000));

    // Underflow of nanos causing underflow of seconds
    assertThrown!Exception(UnixTimeHiRes(time_t.min + 1000, -500) - UnixTimeHiRes(1000, 999_999_500));

    // Diff max and max times
    diff = UnixTimeHiRes(time_t.max, 999_999_999) - UnixTimeHiRes(time_t.max, 999_999_999);

    assert(diff.seconds == 0);
    assert(diff.nanos == 0);

    // Positive to negative
    diff = UnixTimeHiRes(0, 500) - UnixTimeHiRes(0, 1000);

    assert(diff.seconds == 0);
    assert(diff.nanos == -500);


    // Negative to positive
    diff = UnixTimeHiRes(0, -500) - UnixTimeHiRes(0, -1000);

    assert(diff.seconds == 0);
    assert(diff.nanos == 500);


    // Negative to zero
    diff = UnixTimeHiRes(-1, 999_999_999) - UnixTimeHiRes(0, -1);

    assert(diff.seconds == 0);
    assert(diff.nanos == 0);
}

unittest
{
    writeln("[UnitTest UnixTimeHiRes] - opCast Systime");

    enum hnsecsToUnixEpoch = UnixTime.unixTimeToStdTime(0);

    auto time = UnixTimeHiRes(0, 0);
    SysTime systime = cast(SysTime)time;
    assert(systime.toUnixTime() == 0);
    assert(systime.stdTime == hnsecsToUnixEpoch);

    time = UnixTimeHiRes(0, 999_999_999);
    systime = cast(SysTime)time;
    assert(systime.toUnixTime() == time.seconds);
    assert(systime.stdTime == hnsecsToUnixEpoch + convert!("nsecs", "hnsecs")(time.nanos));

    time = UnixTimeHiRes(5_000, 0);
    systime = cast(SysTime)time;
    assert(systime.toUnixTime() == time.seconds);
    assert(systime.stdTime == hnsecsToUnixEpoch + convert!("seconds", "hnsecs")(time.seconds));

    time = UnixTimeHiRes(1_470_014_173, 172_399);
    systime = cast(SysTime)time;
    assert(systime.toUnixTime() == time.seconds);
    assert(systime.stdTime == hnsecsToUnixEpoch + convert!("seconds", "hnsecs")(time.seconds) + convert!("nsecs", "hnsecs")(time.nanos));

    time = UnixTimeHiRes(SysTime.max().toUnixTime(), 0);
    systime = cast(SysTime)time;
    assert(systime.toUnixTime() == time.seconds);
    assert(systime.stdTime == hnsecsToUnixEpoch + convert!("seconds", "hnsecs")(time.seconds));

    time = UnixTimeHiRes(SysTime.max().toUnixTime(), SysTime.max().fracSecs.split!("seconds", "nsecs")().nsecs);
    systime = cast(SysTime)time;
    assert(systime.toUnixTime() == time.seconds);
    assert(systime.stdTime == hnsecsToUnixEpoch + convert!("seconds", "hnsecs")(time.seconds) + convert!("nsecs", "hnsecs")(time.nanos));

    time = UnixTimeHiRes(SysTime.min().toUnixTime(), 0);
    systime = cast(SysTime)time;
    assert(systime.toUnixTime() == time.seconds);
    //TODO fix when phobos bug fixed
    //assert(systime.stdTime == hnsecsToUnixEpoch - convert!("seconds", "hnsecs")(time.seconds));

    //time = UnixTimeHiRes(SysTime.min().toUnixTime(), SysTime.min().fracSecs.split!("seconds", "nsecs")().nanos);
    //systime = cast(SysTime)time;
    //assert(systime.toUnixTime() == time.seconds);
    //assert(systime.stdTime == hnsecsToUnixEpoch - convert!("seconds", "hnsecs")(time.seconds) - convert!("nsecs", "hnsecs")(time.nanos));
}

unittest
{
    writeln("[UnitTest UnixTimeHiRes] - opCast time_t");

    auto time = UnixTimeHiRes(0, 0);
    assert(cast(time_t)time == 0);

    time = UnixTimeHiRes(time_t.max, 999_999_999);
    assert(cast(time_t)time == time_t.max);

    time = UnixTimeHiRes(time_t.min, -999_999_999);
    assert(cast(time_t)time == time_t.min);
}

unittest
{
    writeln("[UnitTest UnixTimeHiRes] - CTFE now");

    UnixTimeHiRes.now!(ClockType.SECOND)();
    UnixTimeHiRes.now!(ClockType.REALTIME)();
    UnixTimeHiRes.now!(ClockType.REALTIME_FAST)();
    UnixTimeHiRes.now!(ClockType.REALTIME_PRECISE)();
    UnixTimeHiRes.now!(ClockType.MONOTONIC)();
    UnixTimeHiRes.now!(ClockType.MONOTONIC_FAST)();
    UnixTimeHiRes.now!(ClockType.MONOTONIC_PRECISE)();
    UnixTimeHiRes.now!(ClockType.UPTIME)();
    UnixTimeHiRes.now!(ClockType.UPTIME_FAST)();
    UnixTimeHiRes.now!(ClockType.UPTIME_PRECISE)();
}

unittest
{
    writeln("[UnitTest UnixTimeHiRes] - now");

    UnixTimeHiRes.now(ClockType.SECOND);
    UnixTimeHiRes.now(ClockType.REALTIME);
    UnixTimeHiRes.now(ClockType.REALTIME_FAST);
    UnixTimeHiRes.now(ClockType.REALTIME_PRECISE);
    UnixTimeHiRes.now(ClockType.MONOTONIC);
    UnixTimeHiRes.now(ClockType.MONOTONIC_FAST);
    UnixTimeHiRes.now(ClockType.MONOTONIC_PRECISE);
    UnixTimeHiRes.now(ClockType.UPTIME);
    UnixTimeHiRes.now(ClockType.UPTIME_FAST);
    UnixTimeHiRes.now(ClockType.UPTIME_PRECISE);
}

unittest
{
    writeln("[UnitTest UnixTimeHiRes] - toString");

    assert(UnixTimeHiRes(0).toString() == "0.000000000");

    assert(UnixTimeHiRes(-100).toString() == "-100.000000000");
    assert(UnixTimeHiRes(-100, 1).toString() == "-99.999999999");
    assert(UnixTimeHiRes(-100, -1).toString() == "-100.000000001");
    assert(UnixTimeHiRes(-100, 999999999).toString() == "-99.000000001");
    assert(UnixTimeHiRes(-100, -999999999).toString() == "-100.999999999");

    assert(UnixTimeHiRes(100).toString() == "100.000000000");
    assert(UnixTimeHiRes(100, 1).toString() == "100.000000001");
    assert(UnixTimeHiRes(100, -1).toString() == "99.999999999");
    assert(UnixTimeHiRes(100, 999999999).toString() == "100.999999999");
    assert(UnixTimeHiRes(100, -999999999).toString() == "99.000000001");
}

unittest
{
    writeln("[UnitTest UnixTime] - opAdd");

    assert(UnixTime(0) + UnixTime(100) == UnixTime(100));
    assert(UnixTime(0) + UnixTime(-100) == UnixTime(-100));
    assert(UnixTime(100) + UnixTime(100) == UnixTime(200));
    assert(UnixTime(100) + UnixTime(-100) == UnixTime(0));
    assert(UnixTime(-100) + UnixTime(100) == UnixTime(0));
    assert(UnixTime(-100) + UnixTime(-100) == UnixTime(-200));

    assert(UnixTime(0) + UnixTime(time_t.max) == UnixTime(time_t.max));
    assert(UnixTime(0) + UnixTime(time_t.min) == UnixTime(time_t.min));
    assert(UnixTime(-1) + UnixTime(-time_t.max) == UnixTime(time_t.min));

    assertThrown!Exception(UnixTime(time_t.max) + UnixTime(1));
    assertThrown!Exception(UnixTime(1) + UnixTime(time_t.max));
    assertThrown!Exception(UnixTime(time_t.min) + UnixTime(-1));
    assertThrown!Exception(UnixTime(-1) + UnixTime(time_t.min));
}

unittest
{
    writeln("[UnitTest UnixTime] - opSub");

    assert(UnixTime(0) - UnixTime(100) == UnixTime(-100));
    assert(UnixTime(0) - UnixTime(-100) == UnixTime(100));
    assert(UnixTime(100) - UnixTime(100) == UnixTime(0));
    assert(UnixTime(100) - UnixTime(-100) == UnixTime(200));
    assert(UnixTime(-100) - UnixTime(100) == UnixTime(-200));
    assert(UnixTime(-100) - UnixTime(-100) == UnixTime(0));

    assert(UnixTime(0) - UnixTime(time_t.max) == UnixTime(time_t.min + 1));
    assert(UnixTime(-1) - UnixTime(time_t.min) == UnixTime(time_t.max));
    assert(UnixTime(-1) - UnixTime(time_t.max) == UnixTime(time_t.min));

    assertThrown!Exception(UnixTime(time_t.min) - UnixTime(1));
    assertThrown!Exception(UnixTime(1) - UnixTime(time_t.min));
    assertThrown!Exception(UnixTime(time_t.max) - UnixTime(-1));
    assertThrown!Exception(UnixTime(-2) - UnixTime(time_t.max));
}

unittest
{
    writeln("[UnitTest UnixTime] - opAdd mixed");

    assert(UnixTime(0) + UnixTimeHiRes(0) == UnixTimeHiRes(0));
    assert(UnixTime(123) + UnixTimeHiRes(123, 123) == UnixTimeHiRes(246, 123));
    assert(UnixTime(-123) + UnixTimeHiRes(123, 123) == UnixTimeHiRes(0, 123));

    assert(UnixTimeHiRes(0) + UnixTime(0) == UnixTimeHiRes(0));
    assert(UnixTimeHiRes(123, 123) + UnixTime(123) == UnixTimeHiRes(246, 123));
    assert(UnixTimeHiRes(123, 123) + UnixTime(-123) == UnixTimeHiRes(0, 123));
}

unittest
{
    writeln("[UnitTest UnixTime] - opSub mixed");

    assert(UnixTime.Epoch - UnixTimeHiRes.Epoch == UnixTimeHiRes(0));
    assert(UnixTime(123) - UnixTimeHiRes(123, 123) == UnixTimeHiRes(0, -123));
    assert(UnixTime(-123) - UnixTimeHiRes(123, 123) == UnixTimeHiRes(-246, -123));

    assert(UnixTimeHiRes(0) - UnixTime(0) == UnixTimeHiRes(0));
    assert(UnixTimeHiRes(123, 123) - UnixTime(123) == UnixTimeHiRes(0, 123));
    assert(UnixTimeHiRes(123, 123) - UnixTime(-123) == UnixTimeHiRes(246, 123));
}

unittest
{
    writeln("[UnixTest UnixTime] - parse");

    assert(UnixTime.parse("0") == UnixTime(0));
    assert(UnixTime.parse("-0") == UnixTime(0));
    assert(UnixTime.parse("1") == UnixTime(1));
    assert(UnixTime.parse("-1") == UnixTime(-1));
}

unittest
{
    writeln("[UnitTest UnixTime] - toString");

    assert(UnixTime.Epoch.toString() == "0");
    assert(UnixTime(100).toString() == "100");
    assert(UnixTime(-100).toString() == "-100");
}

unittest
{
    writeln("[UnitTest UnixTime] - CTFE now");

    UnixTime.now!(ClockType.SECOND)();
    UnixTime.now!(ClockType.REALTIME)();
    UnixTime.now!(ClockType.REALTIME_FAST)();
    UnixTime.now!(ClockType.REALTIME_PRECISE)();
    UnixTime.now!(ClockType.MONOTONIC)();
    UnixTime.now!(ClockType.MONOTONIC_FAST)();
    UnixTime.now!(ClockType.MONOTONIC_PRECISE)();
    UnixTime.now!(ClockType.UPTIME)();
    UnixTime.now!(ClockType.UPTIME_FAST)();
    UnixTime.now!(ClockType.UPTIME_PRECISE)();
}

unittest
{
    writeln("[UnitTest UnixTime] - now");

    UnixTime.now(ClockType.SECOND);
    UnixTime.now(ClockType.REALTIME);
    UnixTime.now(ClockType.REALTIME_FAST);
    UnixTime.now(ClockType.REALTIME_PRECISE);
    UnixTime.now(ClockType.MONOTONIC);
    UnixTime.now(ClockType.MONOTONIC_FAST);
    UnixTime.now(ClockType.MONOTONIC_PRECISE);
    UnixTime.now(ClockType.UPTIME);
    UnixTime.now(ClockType.UPTIME_FAST);
    UnixTime.now(ClockType.UPTIME_PRECISE);
}
