// ==UserScript==
// @name Important Server Data
// @namespace server
// @include https://us.cloudcontrol.rackspacecloud.com/customer/*/first_gen_servers/*
// @include https://us.cloudcontrol.rackspacecloud.com/customer/*/next_gen_servers/*
// @include https://lon.cloudcontrol.rackspacecloud.com/customer/*/first_gen_servers/*
// @include https://lon.cloudcontrol.rackspacecloud.com/customer/*/next_gen_servers/*
// @include https://cloudcontrol.rackspacecloud.com/customer/*/first_gen_servers/*
// @include https://cloudcontrol.rackspacecloud.com/customer/*/next_gen_servers/*
// @include https://uk.cloudcontrol.rackspacecloud.com/customer/*/first_gen_servers/*
// @include https://uk.cloudcontrol.rackspacecloud.com/customer/*/next_gen_servers/*
// @version 2.0
// @grants none
// ==/UserScript==
/* Script written by Tim Taylor, timothy.taylor@rackspace.com */
/* Script updated by Dave Coon, davide.coon@rackspace.com */
function checkdc() {
  if (nglocd != null) {
    dc = 'DFW';
    huddle = dfwfg;
  }
  if (ngloco != null) {
    dc = 'ORD';
    huddle = ordfg;
  }
  if (ngloci != null) {
    dc = 'IAD';
  }
  if (nglocs != null) {
    dc = 'SYD';
  }
  if (nglock != null) {
    dc = 'HKG';
  }
  if (nglocl != null) {
    dc = 'LON';
    huddle = lonfg;
  }
  if (dc == null) {
    dc = 'MISSING, Check for update! https://github.rackspace.com/davi6646/IRC-Escalations';
  }
}
function checkgen() {
  if (isngen == null) {
    firstgen = 'yes';
  } 
  else if (isfgen == null) {
    nextgen = 'yes';
  } 
  else {
    hugeerror = 'checkgen error';
  }
}
function datalist() {
  if (firstgen === 'yes') {
    if (dc == 'LON') {
      bslink = backslinkuk;
    } 
    else {
      bslink = backslink;
    }
    writediv.innerHTML = '!esc new ' + ddishort + ' | ' + pshost + ':' + bslink;
    linnew.parentNode.insertBefore(writediv, linnew);
  } 
  else if (nextgen === 'yes') {
    displaystr = String(displaystr).substr(4);
    if (computenode == null) {
      computenode = ' ';
    }
    if (computenode2 == null) {
      computenode2 = ' ';
    }
    writediv.innerHTML = '!esc new ' + ddishort + ' | Region: ' + dc + ' | ' + 'UUID: ' + displaystr + ' | Node: ' + computenode + computenode2 + ' | ' + serverid; 
    linnew.parentNode.insertBefore(writediv, linnew);
  } 
  else {
    hugeerror = 'datalist error';
  }
}
var bodytext = document.body.innerHTML;
var isfgen = bodytext.match('FirstGen.Server');
var isngen = bodytext.match('NextGen.Server');
var nextgen = 'no';
var firstgen = 'no';
var dc = null;
var nglocd = bodytext.match('DFW');
var ngloco = bodytext.match('ORD');
var nglocl = bodytext.match('LON');
var ngloci = bodytext.match('IAD');
var nglocs = bodytext.match('SYD');
var nglock = bodytext.match('HKG');
var huddle = null;
var dfwfg = bodytext.match('[0-9]+..DFW..');
var ordfg = bodytext.match('[0-9]+..ORD..');
var lonfg = bodytext.match('[0-9]+..LON..');
var pshost = bodytext.match('Host');
var computenode = bodytext.match('c.[0-9]+-[0-9]+-[0-9]+-[0-9]+');
var computenode2 = bodytext.match('compute-[0-9]+-[0-9]+-[0-9]+-[0-9]+');
var serverid = bodytext.match('https://alerts.ohthree.com/nova/.../instance/........-....-....-....-............');
var displaystr = bodytext.match('.../........-....-....-....-............');
var ddi = bodytext.match('Customer [0-9]*');
var ddishort = String(ddi).match('[0-9]+');
var hostip = bodytext.match('\t10.[0-9]+.[0-9]+.[0-9]+');
var backslink = bodytext.match('https://backstage.slicehost.com/slices/[0-9]+');
var backslinkuk = bodytext.match('https://uk-backstage.slicehost.com/slices/[0-9]+');
var alertslink = bodytext.match ('https://alerts.ohthree.com/+');
var hugeerror = 0;
var writediv = document.createElement('div');
var linnew = document.getElementById('content');
checkdc();
checkgen();
datalist();



