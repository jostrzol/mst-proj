<script lang="ts">
	import { NumberStepper, Switch } from 'svelte-ux';

	export interface PidParameters {
		proportional: {
			enabled: boolean;
			factor: number;
		};
		integration: {
			enabled: boolean;
			time: number;
		};
		differentiation: {
			enabled: boolean;
			time: number;
		};
	}
	export interface Props {
		parameters: PidParameters;
		onchange?(params: PidParameters): void;
	}

	const { onchange, parameters }: Props = $props();
	const { proportional, integration, differentiation } = $derived(parameters);
</script>

<NumberStepper
	class="w-48 min-w-35"
	value={proportional.factor}
	disabled={!proportional.enabled}
	on:change={(e) => {
		onchange?.call(null, {
			...parameters,
			proportional: { ...proportional, factor: e.detail.value },
		});
	}}
	label="Proportional factor"
	step={0.01}
/>
<Switch
	class="-mr-2 -ml-4 rotate-90"
	checked={proportional.enabled}
	on:change={() => {
		onchange?.call(null, {
			...parameters,
			proportional: { ...proportional, enabled: !proportional.enabled },
		});
	}}
/>

<NumberStepper
	class="w-48 min-w-33"
	value={integration.time}
	disabled={!integration.enabled}
	on:change={(e) => {
		onchange?.call(null, { ...parameters, integration: { ...integration, time: e.detail.value } });
	}}
	label="Integration time"
	step={0.01}
/>
<Switch
	class="-mr-2 -ml-4 rotate-90"
	checked={integration.enabled}
	on:change={() => {
		onchange?.call(null, {
			...parameters,
			integration: { ...integration, enabled: !integration.enabled },
		});
	}}
/>

<NumberStepper
	class="w-48 min-w-38"
	value={differentiation.time}
	disabled={!differentiation.enabled}
	on:change={(e) => {
		onchange?.call(null, {
			...parameters,
			differentiation: { ...differentiation, time: e.detail.value },
		});
	}}
	label="Differentiation time"
	step={0.01}
/>
<Switch
	class="-mr-2 -ml-4 rotate-90"
	checked={differentiation.enabled}
	on:change={() => {
		onchange?.call(null, {
			...parameters,
			differentiation: { ...differentiation, enabled: !differentiation.enabled },
		});
	}}
/>
