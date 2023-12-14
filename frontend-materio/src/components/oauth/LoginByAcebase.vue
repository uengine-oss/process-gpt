<template>
    <v-card>
        <v-tabs v-model="tab"
                align-tabs="center"
        >
            <v-tab value="main">LOGIN</v-tab>
            <v-tab value="signUp">Sign Up</v-tab>
        </v-tabs>

        <v-window v-model="tab">
            <v-window-item value="main">
                <v-card-text>
                    <span>
                        ※ Please ensure 3rd party cookies are enabled if login fails.
                    </span>
                    <v-text-field
                            v-model="userInfo.email"
                            :rules="[rules.emailRequired, rules.emailMatch]"
                            label="Email"
                            class="my-3"
                    ></v-text-field>

                    <v-text-field
                            v-model="userInfo.password"
                            label="Password"
                            :append-icon="passwordShow ? 'mdi-eye' : 'mdi-eye-off'"
                            :rules="[rules.required]"
                            :type="passwordShow ? 'text' : 'password'"
                            @click:append="passwordShow = !passwordShow"
                            @keydown.enter="signInAcebase()"
                    ></v-text-field>

                    <div v-if="loginText.length > 0" class="mt-3">
                        {{ loginText }}
                    </div>
                </v-card-text>

                <v-card-actions>
                    <v-btn @click="signInAcebase()" block>
                        Sign In
                    </v-btn>
                </v-card-actions>
            </v-window-item>

            <v-window-item value="signUp">
                <v-card-text>
                    <v-text-field
                            v-model="userInfo.username"
                            label="NAME"
                            class="mb-3"
                    ></v-text-field>

                    <v-text-field
                            v-model="userInfo.email"
                            :rules="[rules.emailRequired, rules.emailMatch]"
                            label="Email"
                            class="mb-3"
                    ></v-text-field>

                    <v-text-field
                            v-model="userInfo.password"
                            label="PASSWORD"
                            :append-icon="passwordShow ? 'mdi-eye' : 'mdi-eye-off'"
                            :rules="[rules.required]"
                            :type="passwordShow ? 'text' : 'password'"
                            @click:append="passwordShow = !passwordShow"
                            @keydown.enter="signUpAcebase()"
                    ></v-text-field>

                    <div v-if="loginText.length > 0" class="mt-3">
                        {{ loginText }}
                    </div>
                </v-card-text>
                
                <v-card-actions>
                    <v-btn @click="signUpAcebase()" block>
                        Sign Up
                    </v-btn>
                </v-card-actions>
            </v-window-item>
        </v-window>
    </v-card>
</template>

<script>
    import CommonStorageBase from "../storage/CommonStorageBase.vue";

    export default {
        mixins: [CommonStorageBase],
        components: {},
        props: {
            loginMsg: {
                type: String,
                default: function () {
                    return null
                }
            }
        },
        data: () => ({
            tab: 'main',
            tenantLogo: null,
            drawer: null,
            guest: false,
            onlyConnectionKey: false,
            guestUserInfo: {
                name: '',
                email: ''
            },
            connectionKey: '',
            userImage: null,
            isConnectionkey: false,
            authorized: null,
            rules: {
                required: value => !!value || 'Required.',
                min: v => v.length >= 8 || 'Min 8 characters',
                emailMatch: v => /.+@.+\..+/.test(v) || 'E-mail must be valid',
                emailRequired: v => !!v || 'E-mail is required',
            },
            passwordShow: false,
            userInfo: {
                email: "",
                password: "",
                username: ""
            },
            loginText: '',
        }),
        watch: {
            "userImage": {
                handler(newVal) {
                    console.log(newVal)
                    var me = this
                    localStorage.setItem("picture", this.userIcon(newVal))
                }
            }
        },
        async created() {
            if (localStorage.getItem('authorized')) {
                this.authorized = true
            } else {
                this.authorized = false
            }
        },
        methods: {
            async signInAcebase() {
                var me = this
                try {
                    // var app = this.getComponent('App')
                    if(this.userInfo.email && this.userInfo.password){
                        var result = await this.signIn('db://login', this.userInfo);
                        if(result){
                            window.localStorage.setItem("author", result.user.email)
                            window.localStorage.setItem("userName", result.user.username)
                            window.localStorage.setItem("email", result.user.email)
                            window.localStorage.setItem("picture", result.user.picture)
                            window.localStorage.setItem("accessToken", result.accessToken)
                            window.localStorage.setItem("uid", result.user.uid)
                            if (result.user.email && result.user.email.includes('@uengine.org')) {
                                window.localStorage.setItem("authorized", 'admin');
                            } else {
                                window.localStorage.setItem("authorized", 'student');
                            }
                            this.writeUserData(result.user.uid, result.user.username, result.user.email, result.user.picture)
                            this.$EventBus.$emit('login', result.accessToken)
                            this.$emit('login')
                            this.$emit('close')
                        }
                    }else{
                        this.loginText = '로그인 실패: 로그인 정보를 확인해주세요.'
                    }
                } catch (e) {
                    if(e.code == 'not_found'){
                        this.loginText = `로그인 실패: 존재하지 않은 계정입니다. ${e}`
                    }else{
                        this.loginText = `로그인 실패: 로그인 정보를 확인해주세요. ${e}`
                    }
                    // alert(e)
                }
            },
            getComponent(componentName) {
                let component = null
                let parent = this.$parent
                while (parent && !component) {
                    if (parent.$options.name === componentName) {
                        component = parent
                    }
                    parent = parent.$parent
                }
                return component
            },
            async signUpAcebase() {
                var me = this
                try {
                    // var app = this.getComponent('App')
                    if(this.userInfo.email && this.userInfo.password && this.userInfo.username){
                        var result = await this.signUp('db://login', this.userInfo);
                        // alert("SignUp Success !")
                        if(result){
                            window.localStorage.setItem("author", result.user.email)
                            window.localStorage.setItem("userName", result.user.username)
                            window.localStorage.setItem("email", result.user.email)
                            window.localStorage.setItem("picture", result.user.picture)
                            window.localStorage.setItem("accessToken", result.accessToken)
                            window.localStorage.setItem("uid", result.user.uid)
                            if (result.user.email && result.user.email.includes('@uengine.org')) {
                                window.localStorage.setItem("authorized", 'admin');
                            } else {
                                window.localStorage.setItem("authorized", 'student');
                            }
                            this.writeUserData(result.user.uid, result.user.username, result.user.email, result.user.picture)

                            this.$EventBus.$emit('login', result.accessToken)
                            this.$emit('login')
                            this.$emit('close')
                        }
                    }else{
                        this.loginText = '가입 실패: 가입 정보를 확인해주세요.'
                    }
                    // app.loginDialog = false
                } catch (e) {
                    if(e.code == "invalid_details") {
                        this.loginText = `가입 실패: 가입 정보를 확인해주세요. ${e}`
                    }else{
                        this.loginText = `가입 실패: 가입 정보를 확인해주세요. ${e}`
                    }
                    console.log(e)
                }
            },
            writeUserData(userId, name, email, imageUrl) {
                var authorized = 'student';

                var obj = {
                    username: name,
                    email: email,
                    profile_picture: imageUrl,
                    state: 'signIn',
                    authorized: authorized,
                    loginDate: Date.now()
                }
                var eObj = {
                    uid: userId,
                    userName: name,
                    profile_picture: imageUrl,
                    email: email,
                }

                this.putObject(`db://users/${userId}`, obj)
                //새로운 로그인 유저
                if (email) {
                    var convertEmail = email.replace(/\./gi, '_')
                    this.putObject(`db://enrolledUsers/${convertEmail}`, eObj)
                }

            },
        },

    }
</script>

