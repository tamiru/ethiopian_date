# frozen_string_literal: true

require_relative "ethiopian_date/version"
require "date"
module EthiopianDate
  class Error < StandardError; end


  # from http://ethiopic.org/Calendars/

  # Constants used

  public

  Nmonths = 12
  MonthDays = [0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
  AmharicMonths = { '1' => 'መስከረም', '2' => 'ጥቅምት', '3' => 'ህዳር', '4' => 'ታህሳስ', '5' => 'ጥር', '6' => 'የካቲት',
                    '7' => 'መጋቢት', '8' => 'ሚያዝያ', '9' => 'ግንቦት', '10' => 'ሰኔ', '11' => 'ሐምሌ', '12' => 'ነሃሴ', '13' => 'ጳጉሜ' }
  AmharicDays = { :Sunday => 'እሁድ', :Monday => 'ሰኞ', :Tuesday => 'ማክሰኞ', :Wednesday => 'ሮብ', :Thursday => 'ሓሙስ', :Friday => 'ኣርብ', :Saturday => 'ቅዳሜ' }

  #Ethiopic: Julian date offset
  JD_EPOCH_OFFSET_AMETE_MIHRET = 1723856 # ዓ/ም

  #Coptic : Julian date offset
  JD_EPOCH_OFFSET_COPTIC = 1824665

  JD_EPOCH_OFFSET_GREGORIAN = 1721426
  JD_EPOCH_OFFSET_AMETE_ALEM = -285019 # ዓ/ዓ

  #Changes from in_date:EthiopicDate to GregorianDate
  #
  #@api public
  #@param  in_date always must be year,month, day in that order
  #@return GregorianDate is returned
  #@example fromEthiopicToGregorian(2004,5,21)

  def fromEthiopicToGregorian(year, month, day)
    #TODO : Handle Exceptions when there is a wrong input
    year = year
    month = month
    day = day
    if (year <= 0)
      era = JD_EPOCH_OFFSET_AMETE_ALEM
    else
      era = JD_EPOCH_OFFSET_AMETE_MIHRET
    end
    jdn = jdn_from_ethiopic(year, month, day, era)
    return gregorian_from_jdn(jdn)
  end

  #Changes from in_date:GregorianDate to EthiopicDate
  #
  #@api public
  #@param  year,month,day in that order
  #@return EthiopicDate is returned
  #@example fromEthiopicToGregorian(2012,5,21)
  def fromGregorianToEthiopic(year, month, day)
    jdn = jdn_from_gregorian(year, month, day)
    if jdn >= JD_EPOCH_OFFSET_AMETE_MIHRET + 365
      era = JD_EPOCH_OFFSET_AMETE_MIHRET
    else
      era = JD_EPOCH_OFFSET_AMETE_ALEM
    end
    r = (jdn - era).modulo(1461)
    n = (r.modulo(365)) + (365 * (r / 1460))
    eyear = 4 * ((jdn - era) / 1461) + r / 365 - r / 1460
    emonth = (n / 30) + 1
    eday = (n.modulo(30)) + 1

    return "#{eyear}-#{emonth}-#{eday}"
  end

  #Date format for Ethiopic date
  #
  #@api public
  #@return a formated Ethiopic date string
  #@example ethiopic_date_format('2004-5-21') will be ጥር  21 ቀን  2004ዓ/ም
  def ethiopic_date_format(ethiopic_date)
    d = ethiopic_date.split('-')
    year = d[0]
    month = d[1]
    day = d[2]
    day = day.to_s.length < 2 ? '0' << day.to_s : day
    return "#{AmharicMonths[month.to_s]} #{day}, #{year}"
  end

  private

  #Calculates the jdn from given Gregorian calendar
  #
  #@api private
  #@return jdn
  def jdn_from_gregorian(year, month, day)
    s = (year / 4) - (year - 1) / 4 - (year / 100) + (year - 1) / 100 + (year / 400) - (year - 1) / 400
    t = (14 - month) / 12
    n = 31 * t * (month - 1) + (1 - t) * (59 + s + 30 * (month - 3) + ((3 * month - 7) / 5)) + day - 1
    j = JD_EPOCH_OFFSET_GREGORIAN + 365 * (year - 1) + (year - 1) / 4 - (year - 1) / 100 + (year - 1) / 400 + n
    return j
  end

  #Calculates the jdn from given Ethiopic calendar
  #
  #@api private
  #@return jdn
  def jdn_from_ethiopic(year, month, day, era)
    jdn = (era + 365) + (365 * (year - 1)) + (year / 4) + (30 * month) + (day - 31)
    return jdn
  end

  def gregorian_from_jdn(jdn)
    date = { :year => -1, :month => -1, :day => -1 }
    r2000 = (jdn - JD_EPOCH_OFFSET_GREGORIAN) % 730485
    r400 = (jdn - JD_EPOCH_OFFSET_GREGORIAN) % 146097
    r100 = r400 % 36524
    r4 = r100 % 1461

    n = (r4 % 365) + 365 * (r4 / 1460)
    s = r4 / 1095
    aprime = 400 * ((jdn - JD_EPOCH_OFFSET_GREGORIAN) / 146097) + (100 * (r400 / 36524)) + (4 * (r100 / 1461)) + (r4 / 365) - (r4 / 1460) - (r2000 / 730484)
    date[:year] = aprime + 1
    t = (364 + s - n) / 306
    date[:month] = t * ((n / 31) + 1) + (1 - t) * (((5 * (n - s) + 13) / 153) + 1)
    n += 1 - (r2000 / 730484)
    date[:day] = n

    if ((r100 == 0) && (n == 0) && (r400 != 0))
      date[:month] = 12
      date[:day] = 31
    else
      MonthDays[2] = isGregorianLeap(date[:year]) ? 29 : 28
      for i in 1..Nmonths
        if (n <= MonthDays[i])
          date[:day] = n
          break
        end
        n -= MonthDays[i]
      end
    end
    gregorian_date = Date.new(date[:year], date[:month], date[:day])

    return gregorian_date
  end

  def isGregorianLeap(year)
    return (year % 4 == 0) && ((year % 100 != 0) || (year % 400 == 0))
  end

  # Your code goes here...
end
