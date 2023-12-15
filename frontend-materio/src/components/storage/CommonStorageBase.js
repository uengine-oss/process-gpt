import StorageBase from "./StorageBase";

export default class CommonStorageBase extends StorageBase {
    constructor(client) {
        super(client);
    }

    async setUserInfo() {
        var me = this;
        var user = null;
        if (localStorage.getItem("accessToken")) {
            me.isLogin = true;
            user = await me.getUserInfo();
        } else {
            me.isLogin = false;
            if (me.userInfo.name) {
                me.isGuestLogin = true;
            } else {
                me.isGuestLogin = false;
            }
        }
        me._setUserInfo(user);
    }

    async loginUser() {
        var me = this;
        await me.setUserInfo();
        if (me.isLogin) {
            if (me.userInfo.email) {
                me.getUserPurchaseLists();
            }
        } else if (!me.isLogin && !me.isGuestLogin) {
            me.initUserInfo();
        }
    }
}