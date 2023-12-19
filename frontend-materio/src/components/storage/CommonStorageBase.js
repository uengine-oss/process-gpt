import StorageBase from "./StorageBase";

export default class CommonStorageBase extends StorageBase {
    constructor(client) {
        super(client);
    }

    async setUserInfo() {
        var me = this;
        var user = null;
        user = await me.getUserInfo();
        if (user) {
            if (user.accessToken) {
                me.isLogin = true;
            } else {
                if (user.name) {
                    me.isGuestLogin = true;
                } else {
                    me.isGuestLogin = false;
                }
            }
        } else {
            me.isLogin = false;
            me.isGuestLogin = false;
        }
        me._setUserInfo(user);
    }

    async loginUser() {
        var me = this;
        await me.setUserInfo();
        if (!me.isLogin && !me.isGuestLogin) {
            me.initUserInfo();
        }
    }

    async logout() {
        var me = this;
        localStorage.clear();
        if (me.isLogin) {
            await me.signOut();
        }
        await me.initUserInfo();
        await me.setUserInfo();
    }
}