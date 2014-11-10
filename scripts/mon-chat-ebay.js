function alertWhenChatStart() {
    var source = document.getElementsByTagName('html')[0].innerHTML;
    var found = source.toLowerCase().search("estimated wait time as of");

    if (!found) {
        document.title = "* ALERT * CHAT ***";
        alert("hi");
    } else {
        document.title = "waiting";
        console.log("not yet begun");
        setTimeout(alertWhenChatStart, 5000);
    }
}
