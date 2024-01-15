<template>
    <div>
        <v-btn v-if="!isLogin"
                color="primary"
                variant="text"
                @click="openLoginDialog"
        >
            Login
        </v-btn>

        <v-badge v-else
                :dot="notifications ? false : true"
                :color="notifications ? 'info' : 'success'"
                location="bottom right"
                :content="notifications ? notifications.length : ''"
        >
            <v-avatar style="cursor: pointer;"
                    color="primary"
                    variant="tonal"
            >
                <v-icon>mdi-account</v-icon>
    
                <!-- SECTION Menu -->
                <v-menu activator="parent"
                        width="230"
                        location="bottom end"
                        offset="14px"
                >
                    <v-list>
                        <!-- 👉 User Avatar & Name -->
                        <v-list-item>
                            <template #prepend>
                                <v-list-item-action start>
                                    <v-badge
                                            dot
                                            color="success"
                                            location="bottom right"
                                    >
                                        <v-avatar color="primary"
                                                size="40"
                                                variant="tonal"
                                        >
                                            <v-icon>mdi-account</v-icon>
                                        </v-avatar>
                                    </v-badge>
                                </v-list-item-action>
                            </template>

                            <template #append>
                                <v-list-item-action start>
                                    <v-badge
                                            color="info"
                                            :content="notifications.length"
                                    ></v-badge>
                                </v-list-item-action>
                            </template>

                            <v-list-item-title class="font-weight-semibold">
                                {{ userName }}
                            </v-list-item-title>
                        </v-list-item>

                        <v-divider class="my-2"></v-divider>
                        
                        <!-- 👉 Logout -->
                        <v-list-item @click="logout">
                            <template #prepend>
                                <v-icon class="me-2"
                                        size="22"
                                >mdi-logout-variant</v-icon>
                            </template>

                            <v-list-item-title>
                                Logout
                            </v-list-item-title>
                        </v-list-item>
                    </v-list>
                </v-menu>
                <!-- !SECTION -->
            </v-avatar>
        </v-badge>

        <!-- Login -->
        <v-dialog v-model="loginDialog" width="500">
            <Login @login="login" />
        </v-dialog>
    </div>
</template>

<script>
    import CommonStorageBase from "@/components/storage/CommonStorageBase";
    import Login from "@/components/oauth/LoginByAcebase.vue";

    export default {
        components: {
            Login
        },
        data: () => ({
            storage: null,
            loginDialog: false,
            notifications: null,
        }),
        computed: {
            isLogin() {
                const token = this.storage.isLogin;
                if (token) {
                    return true;
                }
                return false;
            },
            userName() {
                const name = this.storage.userInfo.name;
                if (name) {
                    return name;
                }
                return "";
            },
        },
        async created() {
            this.storage = new CommonStorageBase(this);
            await this.storage.loginUser();

            if (this.storage.userInfo && this.storage.userInfo.name) {
                this.getNotifications();
            }
        },
        methods: {
            openLoginDialog() {
                this.loginDialog = true;
            },
            closeLoginDialog() {
                this.loginDialog = false;
            },
            async login(token) {
                if (token) {
                    await this.storage.loginUser();
                    this.closeLoginDialog();
                    window.location.reload();
                }
            },
            async logout() {
                await this.storage.logout();
                window.location.reload();
            },
            async getNotifications() {
                const uid = this.storage.userInfo.uid;
                await this.storage.watch(`db://users/${uid}`, (callback) => {
                    if (callback) {
                        if (callback.notifications) {
                            let notiList = Object.values(callback.notifications);
                            notiList = notiList.filter(noti => !noti.isChecked);
                            this.notifications = notiList;
                        }
                    }
                });
            }
        }
    }
</script>

