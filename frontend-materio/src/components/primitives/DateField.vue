<template>
    <div class="my-3">
        <div v-if="editMode">
            {{ label }}
            <VDatePicker v-model="date">
                <template #default="{ inputValue, inputEvents }">
                    <!-- <v-text-field
                            v-model="filteredDate"
                            @click="togglePopover"
                            readonly
                            density="compact"
                            prepend-icon="mdi-calendar"
                    ></v-text-field> -->
                    <BaseInput :value="inputValue" v-on="inputEvents" />
                </template>
            </VDatePicker>
            
            <!-- <v-btn v-if="calendarMode" 
                    @click="closeCalendar" 
                    variant="text" 
                    color="black"
            >
                완료
            </v-btn> -->
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
        this.date = this.modelValue
        if(!this.date) {
            this.date = new Date()
        }
    },
    computed:{
        // filteredDate(){
        //     if(this.date) {
        //         this.formattedDate = new Date(this.date).toISOString().substr(0, 10);
        //         return this.formattedDate;            
        //     }
        //     return null;
        // }
    },
    mounted() {
    },
    watch: {
        date: {
            handler(newVal) {
                console.log(newVal)
                // this.change();
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
        openCalendar(){
            this.calendarMode = true
        },
        closeCalendar(){
            this.calendarMode = false;
        }
    }
}
</script>