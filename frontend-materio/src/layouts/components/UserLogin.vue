<template>
    <div>
        <v-avatar v-if="!isLogin" 
                style="cursor: pointer;"
                color="grey"
                variant="tonal"
                @click="loginPage()"
        >
            <v-icon>mdi-account</v-icon>
        </v-avatar>

        <v-badge v-else
                dot
                color="success"
                offset-x="3"
                offset-y="3"
                location="bottom right"
                bordered
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
                                    <v-badge dot
                                            color="success"
                                            offset-x="3"
                                            offset-y="3"
                                            location="bottom right"
                                            bordered
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

                            <v-list-itemTitle class="font-weight-semibold">
                                {{ userName }}
                            </v-list-itemTitle>
                        </v-list-item>

                        <v-divider class="my-2"></v-divider>
                        
                        <!-- 👉 Logout -->
                        <v-list-item>
                            <template #prepend>
                                <v-icon class="me-2"
                                        size="22"
                                >mdi-logout-variant</v-icon>
                            </template>

                            <v-list-itemTitle>Logout</v-list-itemTitle>
                        </v-list-item>
                    </v-list>
                </v-menu>
                <!-- !SECTION -->
            </v-avatar>
        </v-badge>
    </div>
</template>

<script>
    import StorageBase from "@/components/storage/CommonStorageBase.vue";

    export default {
        mixins: [StorageBase],
        data: () => ({
            userName: "",            
        }),
        methods: {
            loginPage() {
                this.loginUser();
            },
        }
    }
</script>

