<template>
    <v-container fluid>
        <v-row>
            <v-sheet v-for="(card, index) in cards"
                    :key="index"
                    elevation="5"
                    height="300"
                    width="300"
                    rounded
                    class="d-flex align-center justify-center flex-wrap text-center mx-auto px-4"
            >
                <div class="d-block">
                    <div class="mb-4">
                        <v-icon color="primary"
                                size="64"
                                :icon="card.icon"
                        ></v-icon>
                    </div>
                    <v-btn rounded
                            :to="card.link"
                            variant="outlined"
                            size="large"
                    >
                        {{ card.text }}
                    </v-btn>
                </div>
            </v-sheet>
        </v-row>
    </v-container>
</template>

<script>
    export default {
        name: 'Index',
        data: () => ({
            cards: [
                {
                    text: "Todolist",
                    link: "/todolist",
                    icon: "mdi-apps"
                },
            ],
        }),
    };
</script>
