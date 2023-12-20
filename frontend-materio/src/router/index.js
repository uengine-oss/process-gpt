import { createRouter, createWebHashHistory } from 'vue-router';

const router = createRouter({
  history: createWebHashHistory(),
  routes: [
    {
      path: '/',
      component: () => import('../components/pages/Index.vue'),
    },
    {
      path: '/organization',
      component: () => import('../components/OrganizationChartChat.vue'),
    },
    {
      path: '/definitions',
      component: () => import('../components/ProcessManagerChat.vue'),
    },
    {
      path: '/definitions/:id',
      component: () => import('../components/ProcessManagerChat.vue'),
    },
    {
      path: '/instances',
      component: () => import('../components/ProcessParticipantChat.vue'),
    },
    {
      path: '/instances/:id',
      component: () => import('../components/ProcessParticipantChat.vue'),
    },
    {
      path: '/todolist',
      component: () => import('../components/ui/TodolistGrid.vue'),
    },
  ],
})

export default router;
