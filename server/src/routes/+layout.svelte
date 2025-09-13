<script lang="ts">
	import '../app.css';

	import {
		AppBar,
		AppLayout,
		getSettings,
		NavItem,
		settings,
		ThemeInit,
		ThemeSwitch,
	} from 'svelte-ux';
	import Fps from '$lib/components/Fps.svelte';
	import { page } from '$app/state';
	import { onNavigate } from '$app/navigation';
	import { faCirclePlay, faHome, faSliders } from '@fortawesome/free-solid-svg-icons';

	settings({
		components: {
			AppLayout: {
				classes: {
					aside: 'border-r',
					nav: 'bg-surface-300 py-2',
				},
			},
			NavItem: {
				classes: {
					root: 'text-sm text-surface-content/70 pl-6 py-2 hover:bg-surface-100/70 relative',
					active:
						'text-primary bg-surface-100 font-medium before:absolute before:bg-primary before:rounded-full before:w-1 before:h-2/3 before:left-[6px] shadow z-10',
				},
			},
		},
	});

	const { showDrawer } = getSettings();
	$showDrawer = false;

	onNavigate(() => {
		$showDrawer = false;
	});

	let { children } = $props();
</script>

<ThemeInit />

<AppLayout>
	<AppBar title="Motor speed regulator" class="bg-surface-100 absolute!">
		<div slot="actions" class="flex gap-4">
			<Fps />
			<ThemeSwitch />
		</div>
	</AppBar>

	<svelte:fragment slot="nav">
		<NavItem text="Home" icon={faHome as unknown as string} currentUrl={page.url} path="/" />
		<NavItem text="Tune" icon={faSliders as unknown as string} currentUrl={page.url} path="/tune" />
		<NavItem
			text="Control"
			icon={faCirclePlay as unknown as string}
			currentUrl={page.url}
			path="/control"
		/>
	</svelte:fragment>

	<main class="flex min-h-screen items-center justify-center">
		{@render children()}
	</main>
</AppLayout>
