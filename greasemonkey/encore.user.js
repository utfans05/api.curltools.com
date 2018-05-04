// ==UserScript==
// @name        Important Server Data Encore
// @namespace   encore.serverdata
// @include     https://apps.encore.rackspace.com/cloud/*
// @require     http://ajax.googleapis.com/ajax/libs/jquery/1.8.3/jquery.min.js
// @require     https://gist.github.com/raw/2625891/waitForKeyElements.js
// @version     1.1
// @grant       none
// ==/UserScript==
/* Script written by Patrick Hudson, patrick.hudson@rackspace.com */
/* Version updated to 1.1 to reflect new include - john.hunneman@rackspace.com
  */
waitForKeyElements (".server-actions", checkIfHidden);

function checkIfHidden(){
    serverInfo = angular.element($('rx-meta[label=Region]')).length;
    regionTest = angular.element($('rx-meta[label=Region]')).text();
    ohthreeTest = $("rx-meta[label='Server ID'] div.definition a.ng-scope").text();
    console.log(serverInfo);
    if(serverInfo > 0 && regionTest != "Region:N/A" && ohthreeTest != ""){
        getServerInfo();
        
    }
    else{
        setTimeout(checkIfHidden,250);
    }
}
function getServerInfo(){
    if ($('.serverInfoESC').length > 0) {
        //console.log("already on page");
    }
    else{
        var pathname = window.location.pathname;
        pathname = pathname.split('/');
        acctNum = pathname[2];
        DC = $("rx-meta[label=Region] div.definition span").text();
        UUID = $("rx-meta[label='Server ID'] div.definition span").text().replace(/[\n\r\s]+/g,'');
        alertsLink = $("rx-meta[label='Server ID'] div.definition a.ng-scope").attr('href');
        escString = "!esc new "+ acctNum + " | Region: " + DC + " | UUID: " + UUID + " | Alerts Link: " + alertsLink;
        $('.page-titles').before('<div class="serverInfoESC"><p>'+ escString +'</p></div>');
    }

}
