#!/bin/bash
# This script checks for user passwords that are about to expire and
# then emails the users to warn them.
# define and initalize loop couter, days of validity and the date
loopcounter=0
todaysdate=$(/bin/date +"%Y%m%d")
daysofvalidity=$(samba-tool domain passwordsettings show | grep "Maximum password age (days):" | egrep -o '[0-9]*$')
howmanydayswarning=6
warningperiodstart=$(expr $daysofvalidity - $howmanydayswarning)
warningperiodend=$(expr $daysofvalidity + $howmanydayswarning)

# ensure that temp files from previous running do not exist
/bin/rm /tmp/smbusernamelist.txt
/bin/rm /tmp/pwexpfixeddate.txt
/bin/rm /tmp/validusers.txt

# define function that will only email valid users
# it takes three inputs - username/email ($1), subject ($2), body text ($3)
function emailvaliduser {
  # gather list of valid email address
  /usr/bin/pdbedit -L -v | egrep "Full Name:"|sed 's/Full Name:            //'|sed '/^$/d'|sed -e 's/\(.*\)/\L\1/'|sed -e 's/ /./g'|sed -e 's/$/\@<YOUR DOMAIN>/' > /tmp/validusers.txt
  # create an array of users that exist in the db
    validusers=( `/bin/cat "/tmp/validusers.txt" `)
  # first check if the account has been disabled in AD
    /usr/bin/pdbedit -L -v | egrep '\[D' -B2 | egrep "Full Name:"|sed 's/Full Name:            //'|sed '/^$/d'|sed -e 's/\(.*\)/\L\1/'|sed -e 's/ /./g'|egrep "$1$" > /dev/null
      if [ $? -ne 0 ]; then
          # ok looks good, their account does not appear to be disabled.
          # now, if the user passed to this function is valid, then send email with a message
            for currentuser in "${validusers[@]}"
              do
              if [ "$currentuser" = "$1" ]
                then
                  echo "$3" | /usr/bin/mail -s " $2 " -a "From:  <YOUREMAIL>" $1
                else
                  # The user does not have a valid google account, so don't try to send them anything
                    echo "$1 no account for user"
                  :
              fi
              done
           else
           # user is disabled? let the administrator know .
           echo "user $1 is disabled and will not be sent an email" | /usr/bin/mail -s "disabled user" <YOURUSERNAME>@<YOURDOMAIN>
      fi
}

# create list of dates for last password change
/usr/bin/pdbedit -L -v | /usr/bin/awk '/Password last/ { print; }' | /usr/bin/awk '{ print $4 " "$5" "$6" "$7 }' > /tmp/datepwlastset.txt

# create user list to match above dates
/usr/bin/pdbedit -L -v | /usr/bin/awk '/Full/ { print; }' | /usr/bin/awk '{ print $3"."$4 }'|sed -e 's/\(.*\)/\L\1/'|sed -e 's/$/\@<YOUR DOMAIN>/' > /tmp/smbusernamelist.txt

# convert date format
/bin/cat /tmp/datepwlastset.txt | while read line ; do /bin/date --date="$line" +"%Y%m%d" ; done > /tmp/pwexpfixeddate.txt

# read usernames into variable
smbuserlist=( `/bin/cat "/tmp/smbusernamelist.txt" `)

# read corrected dates into variable
smbdatelist=( `/bin/cat "/tmp/pwexpfixeddate.txt" `)

# sanity check, make sure that number of users and password dates match
if [ ${#smbuserlist[@]} != ${#smbdatelist[@]} ]
  then
    echo "WARNING! Number of users and password dates do not match."
    echo "(perhaps the smb database was updated during initialization)"
    exit 1
fi

# main loop for checking and taking action
for smbcurrentuser in "${smbuserlist[@]}"
  do
    # calculate expiry date for this user
      if [ ${smbdatelist[$loopcounter]} != $todaysdate ]
        then
          let howoldpw=$(( ( $(/bin/date +"%s") - $(/bin/date --date=${smbdatelist[$loopcounter]} +"%s") )/60/60/24 ))
        else
          # skip this one because the last change date is today or unset
          howoldpw=1
      fi
    # depending on how old the password is; take action
    if ([ "$howoldpw" -gt "$warningperiodstart" ] && [ "$howoldpw" -lt "$daysofvalidity" ])
       then
          emailvaliduser $smbcurrentuser "Password expiry warning" "Your <YOUR DOMAIN> Active Directory password will expire in $((daysofvalidity - howoldpw)) days. To avoid any problems with your login, please change it before expiry. To change your password simply press CTRL+ALT+DEL and follow the prompts. For VPN users; navigate to https://passwd.int.partium.io set it there."
    fi
    if [ "$howoldpw" -eq "$daysofvalidity" ]
       then
          emailvaliduser $smbcurrentuser "Password expiry warning" "Your <YOUR DOMAIN> Active Directory password will expire today. To avoid any problems with your login, please change it before expiry. To change your password simply press CTRL+ALT+DEL and follow the prompts. For VPN users; navigate to https://passwd.int.partium.io set it there."
    fi
    if ([ "$howoldpw" -gt "$daysofvalidity" ] && [ "$howoldpw" -lt "$warningperiodend" ])
       then
          emailvaliduser $smbcurrentuser "Password expired" "Your <YOUR DOMAIN> Active Directory password has expired. If you are having problems accessing your account please contact IT on Teams."
    fi
    let loopcounter=loopcounter+1
  done
# end of script
