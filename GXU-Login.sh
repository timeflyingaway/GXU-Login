#!/bin/sh

logger -t 【GXU-Login】 "开始运行"

##校园网账号（学号、工号）
account=20xxxxxxxx
##校园网密码
password=xxxxxx
##运营商，校园网留空，移动“cmcc”，联通“unicom”，电信“telecom”
isp=telecom

##curl超时时间（s）
timeout=3
##最大尝试次数（重启WAN或者重启路由器重置计数）
max_try=3
##连网后检测间隔（s）
check_time=5

restart_wan() {
  if ! $(return $restarted); then
    /sbin/restart_wan
    sleep 5
    max_try=`expr $err + $max_try - 1`
    restarted=0
    logger -t 【GXU-Login】 "已重启WAN"
  else
    logger -t 【GXU-Login】 "准备重启路由器"
    reboot
    exit 1
  fi
}

check_login() {
  ##获取网络状态
  source=$(curl -s --connect-timeout $timeout http://baidu.com)
  #echo $source
  
  if [ -z "$source" ]; then
    #echo "无网络"
    #logger -t 【GXU-Login】 "无网络"
    return 2
  elif [ -n "$(echo $source | grep www.baidu.com)" ]; then
    #echo "已联网"
    #logger -t 【GXU-Login】 "已联网"
    return 0
  else
    #echo "未联网"
    #logger -t 【GXU-Login】 "未联网"
    return 1
  fi
}

get_info() {
  ##ip:"172.28.x.x"
  ip=$(echo $source | awk -F "<NextURL>" '{print $2}' | awk -F ['&''?'] '{print $2}' | awk -F ['='] '{print $2}')
  #echo $ip

  ##wlanacname:"wlanacname=null"
  wlanacname=$(echo $source | awk -F "<NextURL>" '{print $2}' | awk -F ['&''?'] '{print $3}')
  #echo $wlanacname

  ##wlanacip:"wlanacip=null"
  wlanacip=$(echo $source | awk -F "<NextURL>" '{print $2}' | awk -F ['&''?'] '{print $4}')
  #echo $wlanacip

  ##mac:"00-00-00-00-00-00"
  mac=$(echo $source | awk -F "<NextURL>" '{print $2}' | awk -F ['&''?'] '{print $5}' | cut -b 13-24)
  mac=$(echo $mac | cut -b 1-2)-$(echo $mac | cut -b 3-4)-$(echo $mac | cut -b 5-6)-$(echo $mac | cut -b 7-8)-$(echo $mac | cut -b 9-10)-$(echo $mac | cut -b 11-12)
  #echo $mac
}

do_logout() {
  curl -G --connect-timeout $timeout "http://172.17.0.2:801/eportal/?c=ACSetting&a=Logout&loginMethod=1&protocol=http%3A&hostname=172.17.0.2&port=&iTermType=1&wlanuserip=${ip}&${wlanacip}&${wlanacname}&redirect=null&session=null&vlanid=undefined&mac=${mac}&ip=${ip}&queryACIP=0&jsVersion=2.4.3"
}

do_login() {
  [ -z $err ] && err=0
  ##断网后，尝试一次直接使用原信息登录，因为此时可能不返回任何网页请求，避免直接重启
  if $(return $changed); then
    if ! check_login; then
      $(return 1)
    fi
  else
    check_login
  fi
  case $? in
    2)
    ##重启WAN后，即使无网络仍然尝试，避免重启WAN后直接重启路由器
    $(return $restarted) && err=`expr $err + 1` && [ $err -le $max_try ] && logger -t 【GXU-Login】 "无网络，第${err}次尝试登录" && return 0
    logger -t 【GXU-Login】 "无网络，准备重启WAN"
    ;;
    1)
    if [ $err -le $max_try ]; then
      err=`expr $err + 1`
      logger -t 【GXU-Login】 "未联网，第${err}次尝试登录"
      ! $(return $changed) && get_info
      curl -G --connect-timeout $timeout "http://172.17.0.2:801/eportal/?c=ACSetting&a=Login&loginMethod=1&protocol=http:&hostname=172.17.0.2&port=&iTermType=1&wlanuserip=${ip}&${wlanacip}&${wlanacname}&redirect=null&session=null&vlanid=0&mac=${mac}&ip=${ip}&enAdvert=0&jsVersion=2.4.3&DDDDD=,0,${account}${isp}&upass=${password}&R1=0&R2=0&R3=0&R6=0&para=00&0MKKey=123456&buttonClicked=&redirect_url=&err_flag=&username=&password=&user=&cmd=&Login="
      return 0
    fi
    ;;
    0)
    logger -t 【GXU-Login】 "已联网"
    status='online'
    err=0
    restarted=1
    return 0
    ;;
  esac
  return 1
}

status='offline'
changed=1
restarted=1

[ -n "$isp" ] && isp=@$isp
while [ 1 ]; do
  case $status in
    online)
    if check_login; then
      sleep $check_time
    else
      status='offline'
      changed=0
      logger -t 【GXU-Login】 "网络断开"
      #do_logout
    fi
    ;;
    offline)
    ! do_login && restart_wan
    ##以下两行区别在于断网后是否执行一次登出，个人实验觉得不登出效果比较好
    #$(return $changed) && do_logout && changed=1
    $(return $changed) && changed=1
    ;;
  esac
done
