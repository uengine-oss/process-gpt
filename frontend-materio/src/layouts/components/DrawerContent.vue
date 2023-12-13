<script setup>
import { VerticalNavLink, VerticalNavSectionTitle } from '@layouts'

import partialParse from "partial-json-parser";
let definitions = [];
let chatList = partialParse(localStorage.getItem("process-definition-conversation"));
chatList = chatList.filter(chat => chat.role == "system");
chatList.forEach(chat => {
    var arr = chat.content.split("--- json ---");
    var content = arr.pop().replace(/<[^>]*>?/g, "\n");
    const definition = partialParse(content);
    definitions.push(definition);
});

</script>

<template>
    <ul>
        <VerticalNavSectionTitle :item="{ heading: '정의 관리' }" />
        <VerticalNavLink
            :item="{
                title: '조직도 정의',
                to: '/organization',
                icon: 'mdi-plus'
            }"
        />
        <VerticalNavLink
            :item="{
                title: '프로세스 정의',
                to: '/definitions',
                icon: 'mdi-plus'
            }"
        />
        <VerticalNavLink
            v-for="definition in definitions"
            :key="definition.processDefinitionId"
            :item="{
                title: definition.processDefinitionName,
                to: `/definitions/${definition.processDefinitionId}`,
            }"
        />
        
        <VerticalNavSectionTitle :item="{ heading: '프로세스 실행' }" />
        <VerticalNavLink
            :item="{
                title: '프로세스 실행',
                to: '/instances',
                icon: 'mdi-plus'
            }"
        />
        
        <VerticalNavSectionTitle :item="{ heading: 'ToDoList' }" />
        <VerticalNavLink
            :item="{
                title: '할 일',
                to: '/todolist',
            }"
        />
    </ul>
</template>
