<template>
    <div class="my-3">
        <div v-if="editMode">
            {{ label }}
            <v-text-field
                    @click="openCalendar"
                    v-model="formattedDate"
                    readonly
                    density="compact"
                    prepend-icon="mdi-calendar"
            ></v-text-field>

            <VDatePicker v-if="calendarMode" v-model="date"
            ></VDatePicker>
            <v-btn v-if="calendarMode" 
                    @click="closeCalendar" 
                    variant="text" 
                    color="black"
            >
                완료
            </v-btn>
        </div>
        <div v-else>
            {{ label }} : {{ formattedDate }}
        </div>
    </div>
</template>

<script>
import 'v-calendar/style.css';

export default {
    props: {
        modelValue: Object,
        editMode: Boolean,
        label: String,
    },
    data: () => ({
        date: new Date(),
        formattedDate: null,
        calendarMode: false,
    }),
    created() {
        this.date = this.modelValue;
        if(!this.date) {
            this.date = new Date();
            this.formattedDate = this.date.toLocaleString('ko-KR').substr(0, 12);
        }
    },
    mounted() {
    },
    watch: {
        date: {
            handler(newVal) {
                if (newVal) {
                    this.formattedDate = newVal.toLocaleString('ko-KR').substr(0, 12);
                }
            },
        },
    },
    methods:{
        change(){
            this.$emit("update:modelValue", this.formattedDate);
        },
        setDate(date){
            this.$refs.menu.save(date)
            this.$emit("update:modelValue", date);
        },
        openCalendar() {
            this.calendarMode = true
        },
        closeCalendar() {
            this.calendarMode = false;
        }
    }
}
</script>