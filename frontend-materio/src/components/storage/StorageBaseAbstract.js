import TenantAware from "./TenantAware";

export default class StorageBaseAbstract extends TenantAware {
    constructor(client) {
        super(client);

        this.accessToken = null;
        this.userInfo = {
            name: null,
            profile: null,
            email: null,
            uid: null,
            savedCoin: 0,
            savedToolTime: 0,
            consultingTime: 0,
            authorized: null,
        };
        this.userImage = null;

        this.isLogin = false;
        this.isGuestLogin = false;
    }

    _getMetadata(path) {
        throw new Error("must be implemented");
    }

    _list(path, metadata, tenant) {
        throw new Error("must be implemented");
    }

    async _get(path, tenant) {
        throw new Error("must be implemented");
    }

    _put(path, string) {
        throw new Error("must be implemented");
    }

    _push(path, string) {
        throw new Error("must be implemented");
    }

    _delete(path) {
        throw new Error("must be implemented");
    }

    _getURL(path, tenant) {
        throw new Error("must be implemented");
    }

    _signUp(path, userInfo) {
        throw new Error("must be implemented");
    }

    _signIn(path, metadata, tenant) {
        throw new Error("must be implemented");
    }

    _signOut(path, metadata, tenant) {
        throw new Error("must be implemented");
    }

    _isConnection(path, callback) {
        throw new Error("must be implemented");
    }

    isConnection(path, callback) {
        return this._isConnection(path, callback);
    }

    watch(path, callback) {
        return this._watch(path, callback);
    }

    async list(path, options, tenant) {
        return await this._list(path, options, tenant);
    }

    list_watch(path, options, callback) {
        return this._list_watch(path, options, callback);
    }

    //delete
    async delete(path) {
        return await this._delete(path);
    }

    async getMetadata(path) {
        return await this._getMetadata(path);
    }

    //get
    async getString(path, tenant) {
        return await this._get(path, tenant);
    }

    async getObject(path, tenant) {
        try {
            var string = await this._get(path, tenant);
            if (typeof string == 'string')
                var data = JSON.parse(string);
            else
                var data = string;

            return data;
        } catch (e) {
            console.log(e);
            return undefined;
        }
    }

    //update
    async putString(path, string) {
        return await this._put(path, string, true);
    }

    async putObject(path, obj) {
        var string = obj;
        if (typeof string == 'object') {
            string = JSON.stringify(obj);
        }
        return await this._put(path, string);
    }

    //put
    async pushString(path, string) {
        return await this._push(path, string, true);
    }

    async pushObject(path, obj) {
        var string = JSON.stringify(obj);
        return await this._push(path, string);
    }

    //set
    async setString(path, string) {
        return await this._set(path, string, true);
    }

    async setObject(path, obj) {
        var string = JSON.stringify(obj);
        return await this._set(path, string);
    }

    isValidatePath(path) {
        return this._isValidatePath(path);
    }

    getRef(auth) {
        return this._getRef(auth);
    }

    async refreshFirebaseIdToken() {
        return await this._refreshFirebaseIdToken();
    }

    async getUserInfo() {
        return await this._getUserInfo();
    }

    async getURL(path, tenant) {
        return await this._getURL(path, tenant);
    }

    _setUserInfo(user) {
        if (user) {
            this.userInfo.name = user.name;
            this.userInfo.profile = user.profile;
            this.userInfo.email = user.email;
            this.userInfo.uid = user.uid;
            this.userInfo.authorized = localStorage.getItem('authorized');
            this.accessToken = user.accessToken;
        } else {
            this.userInfo.name = localStorage.getItem('userName');
            this.userInfo.profile = localStorage.getItem('picture');
            this.userInfo.email = localStorage.getItem('email');
            this.userInfo.uid = localStorage.getItem('uid');
            this.userInfo.authorized = localStorage.getItem('authorized');
            this.accessToken = localStorage.getItem('accessToken');
        }
    }

    async signUp(path, userInfo) {
        return await this._signUp(path, userInfo);
    }

    async signIn(path, userInfo) {
        return await this._signIn(path, userInfo);
    }

    async signOut(path, userInfo) {
        return await this._signOut(path, userInfo);
    }

    initUserInfo() {
        this.userInfo.name = null;
        this.userInfo.profile = null;
        this.userInfo.email = null;
        this.userInfo.uid = null;
        this.userInfo.authorized = null;
        this.accessToken = null;
        this.userInfo.savedCoin = 0;
        this.userInfo.savedToolTime = 0;
        this.userInfo.consultingTime = 0;
    }

    async getUserPurchaseLists() {
        var me = this
        if (me.isLogin) {
            try {
                var convertEmail = me.userInfo.email.replace(/\./gi, '_')
                var version = 0
                version = await me.getString(`db://enrolledUsers/${convertEmail}/version`)

                me.watch(`db://enrolledUsers/${convertEmail}/purchaseItemSnapshots/coin`, function (item) {
                    if (item) {
                        me.userInfo.savedCoin = Number(item)
                    } else {
                        me.userInfo.savedCoin = 0
                    }
                });
                me.watch(`db://enrolledUsers/${convertEmail}/purchaseItemSnapshots/ideTime`, function (item) {
                    if (item) {
                        me.userInfo.savedToolTime = Number(item)
                    } else {
                        me.userInfo.savedToolTime = 0
                    }
                });
                me.watch(`db://enrolledUsers/${convertEmail}/purchaseItemSnapshots/consultingTime`, function (item) {
                    if (item) {
                        me.userInfo.consultingTime = Number(item)
                    } else {
                        me.userInfo.consultingTime = 0
                    }
                });
            } catch (e) {
                console.log(e)
                alert(e)
            }
        }
    }
    
};
