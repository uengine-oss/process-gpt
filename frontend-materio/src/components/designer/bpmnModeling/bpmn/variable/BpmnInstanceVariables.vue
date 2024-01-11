<template>
    <v-card outlined class="px-3 py-3 my-2">
        <v-card-text>
            <div v-for="(parameterContext, idx) in parameters" :key="idx">
                <v-row>
                    <v-col v-if="forSubProcess" cols="4">
                        <v-select
                                v-if="calleeDefinition" 
                                v-model="parameters[idx].argument.text"
                                :items="calleeDefinition.processVariableDescriptors"
                                item-text="name"
                                item-value="name"
                                label="피호출측 변수"
                        ></v-select>
                        <v-text-field
                                v-else 
                                v-model="parameters[idx].argument.text"
                                label="input" 
                                id="input"
                        ></v-text-field>
                    </v-col>

                    <v-col v-else cols="4">
                        <v-text-field 
                                name="input"
                                id="input"
                                label="아규먼트"
                                v-model="parameters[idx].argument.text"
                        ></v-text-field>
                    </v-col>
                
                    <v-col v-if="parameterContext.transformerMapping" cols="3">
                        <v-select
                                :value="parameters[idx].transformerMapping.transformer"
                                style="min-width: 20px;"
                                :items="transformerList"
                                label="변환"
                        ></v-select>
                    </v-col>

                    <v-col cols="2">
                        <v-select
                                :value="parameters[idx].direction"
                                @change="changed()"
                                style="min-width: 20px;" 
                                :items="connectDirections"
                                label="연결방향"
                        >
                            <template v-slot:selection>
                                <v-icon>{{ iconForDirection(parameters[idx].direction) }}</v-icon>
                            </template>
                            
                            <template v-slot:item="data">
                                <div v-if="data.item != 'OUT '">
                                    <v-icon>{{iconForDirection(data.item)}}</v-icon>
                                </div>
                                <div v-else>
                                    <v-icon>all_inclusive</v-icon><v-icon>{{iconForDirection(data.item)}}</v-icon>
                                </div>
                            </template>
                        </v-select>
                    </v-col>
                    <v-col cols="1">
                        <v-btn icon color="grey" class="px-0"
                        @click="removeMapping(parameterContext)">
                            <v-icon>delete</v-icon>
                        </v-btn>
                    </v-col>
                </v-row>
            </div>
        </v-card-text>

       <v-card-actions>
            <v-spacer></v-spacer>
            <v-btn text color="primary"
                    class="my-3"
                    @click="addMapping">
                Add Mapping
            </v-btn>
        </v-card-actions>
    </v-card>
</template>

<script>

    export default {
        name: "bpmn-instance-variables",
        props: {
            forSubProcess: Boolean,
            value: Array
        },
        data: function () {
            return {
                parameters: {},
                calleeDefinition: null,
                transformerList: [
                    { _type: null, entityType: null, text: '형태소 추출', disabled: true },
                    { _type: 'org.uengine.five.kernel.SemanticTransformer', entityType: 'SN', text: '숫자' },
                    { _type: 'org.uengine.five.kernel.SemanticTransformer', entityType: 'NNP', text: '이름' },
                    { _type: 'org.uengine.five.kernel.SemanticTransformer', entityType: 'NNG', text: '직업' },
                ],
                connectDirections: [ 'IN-OUT', 'IN', 'OUT', 'OUT ' ]
            };
        }
    }

</script>


